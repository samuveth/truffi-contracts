// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

uint256 constant decimals = 9;
uint256 constant slots = 50;
uint256 constant reveal = 2;

struct SInscription { uint256 seed; uint256 extra; address creator; }
struct SPool { uint256 level; uint256 amount; uint256 createdAt; address addr; address owner; uint256 index; }
struct SPermit { address addr; address owner; uint256 createdAt; bool allowExchanger; uint256 seed; uint256 range; }
struct SSettings { uint256 permitCooldown; uint256 permitExpiration; uint256 exchangeFee; uint256 switchFee; uint256 destroyCooldown; address exchanger; }

interface ITruffi {
  function inscriptionOfOwnerByIndex(address, uint256) external pure returns (SInscription memory);
  function inscriptionCount(address) external view returns (uint256);
}

library DecimalsLib {
  function toDec(uint256 value) internal pure returns (uint256) { return value * 10 ** decimals; }
}

contract Pool {
  using SafeERC20 for IERC20;
  using Address for address payable;
  address immutable token;
  address immutable manager;

  modifier onlyPoolManager() { require(manager == msg.sender, "Only Pool manager can execute the transaction"); _; }

  constructor(address token_, address manager_) {
    token = token_;
    manager = manager_;
  }

  receive() external payable {}

  function safeTransfer(address to, uint256 amount) external onlyPoolManager returns(bool) { IERC20(token).safeTransfer(to, amount); return true; }
  function withdrawFee(uint256 amount) external onlyPoolManager returns(bool) { payable(manager).sendValue(amount); return true; }
}

contract Pools is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using DecimalsLib for uint256;
  using Address for address payable;

  address immutable token;
  uint256[5] thresholds = [1275, 16225, 61225, 106225, 151225];
  uint256[5] sizes = [1, 300, 1200, 2100, 3000];

  SSettings public settings = SSettings(2, 30, 5000 * 10 ** 10, 0, 24 * 1800, address(0));

  mapping(address => address) ownerships;
  mapping(address => SPool) pools;
  mapping(uint256 => address) indexes;

  uint256 public activePoolCount = 0;
  uint256 public exchangeCount = 0;

  mapping(address => uint256) fees;
  mapping(address => SPermit) permits;

  event OnCreate(SPool);
  event OnDestroy(SPool);
  event OnRefresh(SPool);
  event OnExchange(uint256 indexed, address indexed, uint256, SPool, SInscription);
  event OnSwitch(SPermit);

  modifier onlyPoolOwner(address addr) {
    require(addr != address(0), "Null address");
    require(ownerships[addr] == msg.sender, "Not the owner of the pool");
    _;
  }

  modifier onlyWithValidPermit(address owner) {
    require(owner != address(0), "Wrong Permits owner address");
    SPermit memory permit = getPermit(owner);
    require(permit.addr != address(0) && ownerships[permit.addr] != address(0), "Not a valid permit");
    require(block.number >= permits[owner].createdAt + settings.permitCooldown, "Permit is on cooldown");
    require(block.number <= permit.createdAt + settings.permitExpiration, "Permit is expired");
    bool validExchanger = settings.exchanger != address(0) && permit.allowExchanger && msg.sender == settings.exchanger;
    require(msg.sender == owner || validExchanger , "Not allowed to use this permit");
    _;
  }

  constructor(address token_) { token = token_; }

  receive() external payable {}

  function changeSettings(SSettings calldata settings_) external onlyOwner {
    require(settings_.permitCooldown >= 2 && settings_.permitCooldown <= 10, "Permit cooldown must be from 2 to 10 blocks");
    require(settings_.permitExpiration >= 15 && settings_.permitExpiration <= 900, "Permit expiration must be from 15 to 900 blocks");
    require(settings_.exchangeFee >= 0 && settings_.exchangeFee <= 100000 * 10 ** 10, "Exchange fee must be from 0 to 0.001 ETH");
    require(settings_.switchFee >= 0 && settings_.switchFee <= 100000 * 10 ** 10, "Switch Pool fee must from 0 to 0.001 ETH");
    require(settings_.destroyCooldown >= 0 && settings_.destroyCooldown <= (24 * 1800), "Destroy Pool cooldown must be from 0 to 43200 blocks");
    settings = settings_;
  }

  function withdraw() external onlyOwner {
    IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    payable(msg.sender).sendValue(address(this).balance);
  }

  function createPool(uint256 amount) external nonReentrant returns(bool) {
    require(getLevel(amount) > 0, "Incorrect token amount");

    address addr = address(new Pool(token, address(this)));
    ownerships[addr] = msg.sender;

    IERC20(token).safeTransferFrom(msg.sender, addr, amount.toDec());

    pools[addr] = SPool(getLevel(amount), amount, block.number, addr, ownerships[addr], activePoolCount);

    for (uint256 i = 0; i < slots; i++) {
      uint256 size = (sizes[pools[addr].level - 1] + i).toDec();
      Pool(payable(addr)).safeTransfer(address(this), size);
      IERC20(token).safeTransfer(addr, size);
		}

    emit OnCreate(pools[addr]);

    indexes[activePoolCount] = addr;
    activePoolCount++;
    return true;
  }

  function refreshPool(address addr) external onlyPoolOwner(addr) nonReentrant returns (bool) {
    Pool(payable(addr)).safeTransfer(address(this), pools[addr].amount.toDec());
    IERC20(token).safeTransfer(addr, pools[addr].amount.toDec());

    for (uint256 i = 0; i < slots; i++) {
      uint256 size = (sizes[pools[addr].level - 1] + i).toDec();
      Pool(payable(addr)).safeTransfer(address(this), size);
      IERC20(token).safeTransfer(addr, size);
		}

    emit OnRefresh(pools[addr]);
    return true;
  }

  function destroyPool(address addr) external onlyPoolOwner(addr) nonReentrant returns(bool) {
    uint256 balance = IERC20(token).balanceOf(addr);
    require(balance > 0, "Pool does not have any tokens");
    require(block.number > pools[addr].createdAt + settings.destroyCooldown, "Pool can be destroyed only after the cooldown period has passed");

    SPool memory pool = pools[addr];

    Pool(payable(addr)).safeTransfer(msg.sender, balance);
    pools[addr] = SPool(0, 0, 0, pool.addr, pool.owner, pool.index);

    emit OnDestroy(pool);
    reindexPools(addr);
    return true;
  }

  function withdrawPoolFees(address addr) public onlyPoolOwner(addr) nonReentrant returns (bool) {
    uint256 balance = payable(addr).balance;
    require(balance > 0, "Pool does not have any fees");

    Pool(payable(addr)).withdrawFee(balance);
    payable(ownerships[addr]).sendValue(fees[addr]);
    fees[addr] = 0;
    return true;
  }

  function exchangeInscription(address owner, uint256 amount, uint256 extra) external payable onlyWithValidPermit(owner) nonReentrant returns(bool) {
    require(msg.value == settings.exchangeFee, "Incorrect exchange eth fee");
    SPermit memory permit = getPermit(owner);
    SPool memory pool = pools[permit.addr];
    require(pool.amount != 0, "Inactive pool");
    require(amount >= sizes[pool.level - 1] && amount < (sizes[pool.level - 1] + slots), "Token amount is not in a pools range");

    address addr = permit.addr;

    SInscription memory inscription = getInscriptionByAmount(amount, addr);

    if(extra != 0) require(inscription.extra == extra, "Inscription is not matching the requirement");

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount.toDec());
    Pool(payable(addr)).safeTransfer(msg.sender, amount.toDec());


    IERC20(token).safeTransfer(addr, 1);
    Pool(payable(addr)).safeTransfer(address(this), 1);

    IERC20(token).safeTransfer(addr, amount.toDec());
    Pool(payable(addr)).safeTransfer(address(this), amount.toDec());
    IERC20(token).safeTransfer(addr, amount.toDec());

    payable(addr).sendValue(settings.exchangeFee);
    fees[addr] = fees[addr] + settings.exchangeFee;

    emit OnExchange(amount, msg.sender, msg.value, pool, inscription);
    exchangeCount++;
    return true;
  }

  function switchPool(bool allowExchanger) external payable returns (SPermit memory) {
    require(permits[msg.sender].createdAt == 0 || permits[msg.sender].createdAt + settings.permitCooldown <= block.number, "Permit can not be changed yet");
    require(msg.value == settings.switchFee, "Incorrect switch eth fee");

    uint256 seed = uint256(keccak256(abi.encodePacked(activePoolCount, block.timestamp, exchangeCount, block.prevrandao)));
    permits[msg.sender] = SPermit(address(0), msg.sender, block.number, allowExchanger && settings.exchanger != address(0), seed, activePoolCount);
    emit OnSwitch(permits[msg.sender]);
    return permits[msg.sender];
  }

  function getPool(address addr) external view returns (SPool memory) { return pools[addr]; }

  function getPoolByIndex(uint256 index) external view returns (SPool memory) { return pools[indexes[index]]; }

  function getPoolFee(address addr) external view returns (uint256) { return fees[addr]; }

  function getPermit(address owner) public view returns (SPermit memory) {
    require(permits[owner].seed != 0, "Permit does not exist");
    if(block.number <= permits[owner].createdAt + reveal) return permits[owner];
    SPermit memory permit = permits[owner];
    uint256 index = uint256(keccak256(abi.encodePacked(permit.seed, blockhash(permit.createdAt + reveal)))) % permit.range;
    return SPermit(indexes[index], permit.owner, permit.createdAt, permit.allowExchanger, permit.seed, permit.range);
  }

  function reindexPools(address addr) internal returns (bool) {
    uint256 index = pools[addr].index;
    address lastPoolsAddr = indexes[activePoolCount - 1];

    pools[lastPoolsAddr].index = index;
    indexes[index] = pools[lastPoolsAddr].addr;
    indexes[activePoolCount - 1] = address(0);

    activePoolCount--;
    return true;
  }

  function getInscriptionByAmount(uint256 amount, address addr) internal view returns (SInscription memory) {
    uint256 count = ITruffi(token).inscriptionCount(addr);
    SInscription memory inscription;

    for(uint256 i = 0; i < count; i++){
      inscription = ITruffi(token).inscriptionOfOwnerByIndex(addr, i);
      if(inscription.seed == amount) return inscription;
    }

    return inscription;
  }

  function getLevel(uint256 amount) private view returns (uint256) {
    for(uint256 i = 0; i < thresholds.length; i++){
      if(thresholds[i] == amount) return i + 1;
    }
    return 0;
  }
}
