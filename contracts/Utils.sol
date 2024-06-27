// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Libs.sol";

uint constant decimals = 9;

struct SPool { uint level; uint amount; uint createdAt; address addr; address owner; uint index; }
struct SPermit { address addr; address owner; uint createdAt; bool allowExchanger; uint seed; uint range; }
struct SVault { uint256 amount; address addr; address owner; address token; uint256 index; }
struct SVaultInscription { address addr; SInscription inscription; }
struct SCollected { uint collectedAt; uint slot; SInscription inscription; }
struct SEvent { uint index; uint start; uint end; uint seed; uint slots; uint prize; uint level; }

interface ITruffi {
  function inscriptionOfOwnerByIndex(address, uint) external pure returns (SInscription memory);
  function inscriptionCount(address) external view returns (uint);
  function transfer(address to, uint amount) external returns (bool);
}

interface IPools {
  function activePoolCount() external view returns (uint);
  function getPoolByIndex(uint) external view returns (SPool memory);
  function exchangeInscription(uint amount, uint extra) external payable returns(bool);
}

interface IEvents {
  function events(uint) external view returns (SEvent memory);
  function getCollected(uint, address) external view returns (SCollected[] memory);
}

interface IVaults {
  function counts(address, address) external view returns (uint);
  function getVaultOfOwnerByIndex(address, address, uint) external view returns (SVault memory);
}

contract Utils {
  address public token;
  address public special;
  address public pools;
  address public vaults;

  using DecimalsLib for uint;
  using MetaLib for SMeta;
  using MetaLib for SInscription;

  constructor(address token_, address special_, address pools_, address vaults_){
    token = token_;
    special = special_;
    pools = pools_;
    vaults = vaults_;
  }

  function getPools() external view returns (SPool[] memory) {
    uint activePoolCount = IPools(pools).activePoolCount();
    SPool[] memory data = new SPool[](activePoolCount);
    for(uint i = 0; i < activePoolCount; i++){ data[i] = IPools(pools).getPoolByIndex(i); }

    return data;
  }

  function getInscriptions(address addr) external view returns (SInscription[] memory) {
    uint count = ITruffi(token).inscriptionCount(addr);
    SInscription[] memory inscriptions = new SInscription[](count);
    for(uint i = 0; i < count; i++){ inscriptions[i] = ITruffi(token).inscriptionOfOwnerByIndex(addr, i); }

    return inscriptions;
  }

  function getInscriptionByAmount(address addr, uint amount) public view returns (SInscription memory) {
    uint count = ITruffi(token).inscriptionCount(addr);
    SInscription memory inscription;

    for(uint i = 0; i < count; i++){
      inscription = ITruffi(token).inscriptionOfOwnerByIndex(addr, i);
      if(inscription.seed == amount) return inscription;
    }

    return inscription;
  }

  function getInscriptionsByVaultsOwner(address owner) public view returns (SVaultInscription[] memory) {
    uint count = IVaults(vaults).counts(token, owner);

    SVault[] memory vault = new SVault[](count);
    SVaultInscription[] memory inscriptions = new SVaultInscription[](count);
    SInscription memory inscription;

    for(uint i = 0; i < count; i++){
      vault[i] = IVaults(vaults).getVaultOfOwnerByIndex(token, owner, i);
      inscription = ITruffi(token).inscriptionOfOwnerByIndex(vault[i].addr, 0);
      inscriptions[i] = SVaultInscription(vault[i].addr, inscription);
    }

    return inscriptions;
  }

  function getMeta(SInscription calldata seed_data) external view returns (string memory){ return getData(seed_data).meta(); }

  function getData(SInscription calldata inscription) public view returns (SMeta memory){ return inscription.data(special); }

  function getMultiData(SInscription[] calldata arr) external view returns (SMeta[] memory){
    uint len = arr.length;
    SMeta[] memory truffies = new SMeta[](len);
    for(uint i = 0; i < len; i++){ truffies[i] = getData(arr[i]); }

    return truffies;
  }

  function getMultiMeta(SInscription[] calldata arr) external view returns (string memory){
    uint len = arr.length;
    string memory str;
    for(uint i = 0; i < len; i++){ str = string(abi.encodePacked(str, i > 0 ? ", " : "", getData(arr[i]).meta())); }

    return string(abi.encodePacked("[", str, "]"));
  }

}
