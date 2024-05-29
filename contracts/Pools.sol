// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

uint constant decimals = 9;
uint constant slots = 50;

struct SInscription { uint256 seed; uint256 extra; address creator; }
struct SPool { uint256 level; uint256 amount; uint256 startedAt; address addr; address owner; }
struct SPermit { address addr; address owner; uint256 createdAt; }
struct SSettings { uint256 permitCooldown; uint256 permitExpiration; uint256 exchangeFee; uint256 switchFee; uint256 refreshFee; uint256 createFee; }

interface ITruffi {
  function inscriptionOfOwnerByIndex(address, uint256) external pure returns (SInscription memory);
  function inscriptionCount(address) external view returns (uint256);
}

library DecimalsLib {
  function toDec(uint256 value) internal pure returns (uint256) { return value * 10 ** decimals; }
}

contract Pool {
  using SafeERC20 for IERC20;
  address immutable token;
  address immutable manager;

  modifier onlyPoolManager() { require(manager == msg.sender, "Only Pool manager can execute the transaction"); _; }

  constructor(address token_, address manager_) {
    token = token_;
    manager = manager_;
  }

  receive() external payable {}

  function safeTransfer(address to, uint256 amount) external onlyPoolManager returns(bool) { IERC20(token).safeTransfer(to, amount); return true; }
  function withdrawFee(uint256 amount) external onlyPoolManager returns(bool) { payable(manager).transfer(amount); return true; }
}

contract Pools is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using DecimalsLib for uint256;
  address immutable token;
  uint256[5] thresholds = [1275, 16225, 61225, 106225, 151225];
  uint256[5] sizes = [1, 300, 1200, 2100, 3000];

  SSettings public settings = SSettings(3, 30, 5000 * 10 ** 10, 0, 25000 * 10 ** 10, 0);

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
  event OnExchange(uint256 indexed, address indexed, SPool, SInscription);
  event OnSwitch(SPermit);

  modifier onlyPoolOwner(address addr) {
    require(addr != address(0), "Null address");
    require(ownerships[addr] == msg.sender, "Not the owner of the pool");
    _;
  }

  modifier onlyWithValidPermit() {
    require(ownerships[permits[msg.sender].addr] != address(0), "Do not have valid permit");
    require(permits[msg.sender].createdAt + settings.permitExpiration >= block.number, "Permit is expired for this pool");
    _;
  }

  constructor(address token_) { token = token_; }

  receive() external payable {}

  function changeSettings(SSettings calldata settings_) external onlyOwner { settings = settings_; }

  function withdraw() external onlyOwner {
    IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    payable(msg.sender).transfer(address(this).balance);
  }

  function createPool(uint256 amount) external payable nonReentrant returns(bool) {
    require(msg.value == settings.createFee, "Incorrect create eth fee");
    require(getLevel(amount) > 0, "Incorrect token amount");

    address addr = address(new Pool(token, address(this)));
    ownerships[addr] = msg.sender;

    IERC20(token).safeTransferFrom(msg.sender, addr, amount.toDec());

    pools[addr] = SPool(getLevel(amount), amount, block.number, addr, ownerships[addr]);

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

  function refreshPool(address addr) external payable onlyPoolOwner(addr) nonReentrant returns (bool) {
    require(msg.value == settings.refreshFee, "Incorrect refresh eth fee");

    Pool(payable(addr)).safeTransfer(address(this), pools[addr].amount.toDec());
    IERC20(token).safeTransfer(addr, pools[addr].amount.toDec() - 1);
    IERC20(token).safeTransfer(addr, 1);

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

    SPool memory pool = pools[addr];

    Pool(payable(addr)).safeTransfer(msg.sender, balance);
    pools[addr] = SPool(0, 0, 0, pool.addr, pool.owner);

    emit OnDestroy(pool);
    reindexPools(addr);
    return true;
  }

  function withdrawPoolFees(address addr) public onlyPoolOwner(addr) returns (bool) {
    uint256 balance = payable(addr).balance;
    require(balance > 0, "Pool does not have any fees");

    Pool(payable(addr)).withdrawFee(balance);
    payable(ownerships[addr]).transfer(fees[addr]);
    fees[addr] = 0;
    return true;
  }

  function exchangeInscription(uint256 amount, uint256 extra) external payable onlyWithValidPermit nonReentrant returns(bool) {
    require(msg.value == settings.exchangeFee, "Incorrect exchange eth fee");
    SPermit memory permit = permits[msg.sender];
    SPool memory pool = pools[permit.addr];
    require(pool.amount != 0, "Inactive pool");
    require(amount >= sizes[pool.level - 1] && amount < (sizes[pool.level - 1] + slots), "Token amount is not in a pools range");

    address addr = permit.addr;

    SInscription memory inscription = getInscriptionByAmount(amount, addr);

    if(extra != 0) require(inscription.extra == extra, "Inscription is not matching the requirement");

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount.toDec());
    Pool(payable(addr)).safeTransfer(msg.sender, amount.toDec());

    IERC20(token).safeTransfer(addr, amount.toDec() - 1);
    IERC20(token).safeTransfer(addr, 1);

    Pool(payable(addr)).safeTransfer(address(this), amount.toDec());
    IERC20(token).safeTransfer(addr, amount.toDec());

    payable(addr).transfer(settings.exchangeFee);
    fees[addr] = fees[addr] + settings.exchangeFee;

    emit OnExchange(amount, msg.sender, pool, inscription);
    exchangeCount++;
    return true;
  }

  function switchPool() external payable returns (SPermit memory) {
    require(permits[msg.sender].createdAt == 0 || permits[msg.sender].createdAt + settings.permitCooldown <= block.number, "Permit can not be changed yet");
    require(msg.value == settings.switchFee, "Incorrect switch eth fee");
    uint256 index = uint256(keccak256(abi.encodePacked(activePoolCount, block.timestamp, exchangeCount, block.prevrandao))) % activePoolCount;
    address addr = indexes[index];
    permits[msg.sender] = SPermit(addr, msg.sender, block.number);
    emit OnSwitch(permits[msg.sender]);
    return permits[msg.sender];
  }

  function getPool(address addr) external view returns (SPool memory) { return pools[addr]; }

  function getPoolByIndex(uint256 index) external view returns (SPool memory) { return pools[indexes[index]]; }

  function getPoolFee(address addr) external view returns (uint256) { return fees[addr]; }

  function getPermit(address addr) external view returns (SPermit memory) { return permits[addr]; }

  function reindexPools(address addr) internal returns (bool) {
    bool offset = false;
    for(uint256 i = 0; i < activePoolCount; i++){
      if(indexes[i] == addr) offset = true;
      if(offset) indexes[i] = indexes[i + 1];
    }
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
