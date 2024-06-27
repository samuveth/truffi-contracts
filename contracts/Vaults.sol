// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract IERC20Extented is IERC20 { function decimals() public virtual view returns (uint8); }

struct SVault { uint256 amount; address addr; address owner; IERC20Extented token; uint256 index; }

library DecimalsLib {
  function toDec(uint256 value, uint256 decimals) internal pure returns (uint256) { return value * 10 ** decimals; }
}

contract Vault {
  using SafeERC20 for IERC20Extented;
  IERC20Extented immutable token;
  address immutable manager;

  modifier onlyVaultManager() { require(manager == msg.sender, "Only Vault manager can execute the transaction"); _; }

  constructor(IERC20Extented token_, address manager_) {
    token = token_;
    manager = manager_;
  }

  function safeTransfer(address to, uint256 amount) external onlyVaultManager returns(bool) { IERC20Extented(token).safeTransfer(to, amount); return true; }
}

contract Vaults is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20Extented;
  using DecimalsLib for uint256;

  mapping(address => address) ownerships;
  mapping(address => SVault) vaults;

  mapping(IERC20Extented => mapping(address => uint256)) public counts;
  mapping(IERC20Extented => mapping(address => mapping(uint256 => address))) indexes;

  mapping(IERC20Extented => uint256) public total;

  event OnCreate(SVault);
  event OnDestroy(SVault);
  event OnTransfer(address indexed, address indexed, SVault);

  modifier onlyVaultOwner(address addr) {
    require(addr != address(0), "Null address");
    require(ownerships[addr] == msg.sender, "Not a owner of the vault");
    _;
  }

  constructor() {}

  function createVault(IERC20Extented token, uint256 amount) external nonReentrant returns(bool) {
    require(amount >= 1, "Minimum 1 token required to create a vault");

    address addr = address(new Vault(token, address(this)));
    ownerships[addr] = msg.sender;

    uint8 decimals = IERC20Extented(token).decimals();
    uint256 count = counts[token][ownerships[addr]];

    IERC20Extented(token).safeTransferFrom(ownerships[addr], addr, amount.toDec(decimals));

    vaults[addr] = SVault(amount, addr, ownerships[addr], token, count);

    indexVault(token, addr, ownerships[addr]);
    total[token]++;

    emit OnCreate(vaults[addr]);
    return true;
  }

  function destroyVault(address addr) external onlyVaultOwner(addr) nonReentrant returns(bool) {
    SVault memory vault = vaults[addr];
    Vault(addr).safeTransfer(ownerships[addr], IERC20Extented(vault.token).balanceOf(addr));

    unindexVault(vault.token, addr, ownerships[addr]);
    total[vault.token]--;

    emit OnDestroy(vault);
    return true;
  }

  function transferVault(address addr, address to) external onlyVaultOwner(addr) nonReentrant returns(bool) {
    require(to != address(0), "Can not transfer to address zero");
    ownerships[addr] = to;

    SVault memory vault = vaults[addr];

    vaults[addr].owner = ownerships[addr];
    
    unindexVault(vault.token, addr, msg.sender);
    vaults[addr].index = counts[vault.token][ownerships[addr]];
    indexVault(vault.token, addr, ownerships[addr]);

    emit OnTransfer(msg.sender, to, vault);
    return true;
  }

  function indexVault(IERC20Extented token, address addr, address owner) internal {
    indexes[token][owner][vaults[addr].index] = addr;
    counts[token][owner]++;
  }

  function unindexVault(IERC20Extented token, address addr, address owner) internal {
    uint256 index = vaults[addr].index;
    uint256 vaultsCount = counts[token][owner];
    address lastVaultsAddr = indexes[token][owner][vaultsCount - 1];

    vaults[lastVaultsAddr].index = index;
    indexes[token][owner][index] = vaults[lastVaultsAddr].addr;
    indexes[token][owner][vaultsCount - 1] = address(0);

    counts[token][owner]--;
  }

  function getVaultOfOwnerByIndex(IERC20Extented token, address owner, uint256 index) external view returns(SVault memory) { return vaults[indexes[token][owner][index]]; }
  function getVault(address addr) external view returns(SVault memory) { return vaults[addr]; }
}
