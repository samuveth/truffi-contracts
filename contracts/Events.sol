// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Ownable.sol";
import "./lib/Libs.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

uint8 constant colors = 10;
uint8 constant decimals = 9;

struct SEvent { uint index; uint start; uint end; uint seed; uint slots; uint prize; uint level; address[] participants; }
struct SSettings { uint collectFee; }
struct SCollected { uint collectedAt; uint slot; SInscription inscription; }

struct SPool { uint256 level; uint256 amount; uint256 createdAt; address addr; address owner; uint256 index; }
struct SPoolsSettings { uint256 permitCooldown; uint256 permitExpiration; uint256 exchangeFee; uint256 switchFee; uint256 destroyCooldown; address exchanger; }

interface ITruffi {
  function inscriptionOfOwnerByIndex(address, uint) external pure returns (SInscription memory);
  function inscriptionCount(address) external view returns (uint);
  function transferFrom(address, address, uint256) external returns (bool);
  function transfer(address, uint256) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint);
  function approve(address spender, uint256 value) external returns (bool);
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
}

interface IPools {
  function activePoolCount() external view returns (uint);
  function getPoolByIndex(uint) external view returns (SPool memory);
  function exchangeInscription(address owner, uint256 amount, uint256 extra) external payable returns(bool);
  function settings() external view returns (SPoolsSettings memory);
}

contract Events is Ownable, ReentrancyGuard {
  using RandLib for SRand;
  using DecimalsLib for uint;
  using Strings for uint;

  address public token;
  address public pools;

  uint16[5] thresholds = [1, 300, 1200, 2100, 3000];

  SSettings public settings = SSettings(5000 * 10 ** 10);

  mapping(uint => SEvent) public events;
  mapping(uint => mapping(address => SCollected[])) public collected;
  mapping(uint => mapping(uint => address[])) collectors;
  uint public total = 7;


  event OnCollect(address indexed collector, uint indexed index, uint indexed slot, SInscription inscription);

  constructor(address token_, address pools_){ token = token_; pools = pools_; }

  function withdraw() external onlyOwner { payable(msg.sender).transfer(address(this).balance); }

  function changeSettings(SSettings calldata settings_) external onlyOwner {
    require(settings_.collectFee >= 0 && settings_.collectFee <= 100000 * 10 ** 10, "Switch Pool fee must be from 0 to 0.001 ETH");
    settings = settings_;
  }

  function startEvent(address[] calldata participants, uint end, uint slots, uint prize, uint level) external onlyOwner {
    require(end >= 1800, "End needs to be at least 1800 blocks away");
    require(checkLastEventIsEnded(), "Previous event is still running");
    require(level >= 0 && level <= 4, "Difficulty level needs to be set between 0 and 4");

    uint seed = uint(keccak256(abi.encodePacked(block.prevrandao, slots, total, blockhash(block.number - 1))));
    events[total] = SEvent(total, block.number, block.number + end, seed, slots, prize, level, participants);

    total++;
  }

  function finishEvent(uint index) external onlyOwner {
    require(events[index].end > block.number, "event is already finished");
    events[index].end = block.number;
  }

  function collect(uint amount, uint index, uint slot) external payable nonReentrant returns(bool) {
    require(msg.value == settings.collectFee, "Incorrect eth fee amount");
    require(amount >= 1, "Send at least 1 token");

    require(ITruffi(token).transferFrom(msg.sender, address(this), amount.toDec(decimals)), "Transfer to contract failed");
    SInscription memory inscription = getInscriptionByAmount(amount, address(this));

    require(inscription.extra != 0, "Incorrect Inscription");

    require(ITruffi(token).transfer(msg.sender, amount.toDec(decimals) - 1), "Transfer back big amount failed");
    require(ITruffi(token).transfer(msg.sender, 1), "Transfer back small amount failed");

    collected[index][msg.sender].push(SCollected(block.number, slot, inscription));
    collectors[index][slot].push(msg.sender);
    emit OnCollect(msg.sender, index, slot, inscription);
    return true;
  }

  function exchangeAndCollect(uint256 amount, uint256 extra, uint index, uint slot) external payable nonReentrant returns(bool) {
    uint exchangeFee = IPools(pools).settings().exchangeFee;

    require(pools != address(0), "In order to exchange owner needs to set the pools address");
    require(ITruffi(token).allowance(msg.sender, address(this)) >= amount.toDec(decimals), "Incorrect token allowance");
    require(msg.value == exchangeFee, "Incorrect inscription exchange eth fee");
    require(amount >= 1, "Send at least 1 token");

    require(ITruffi(token).transferFrom(msg.sender, address(this), amount.toDec(decimals)), "Transfer to contract failed");

    ITruffi(token).increaseAllowance(pools, amount.toDec(decimals));
    require(IPools(pools).exchangeInscription{value: exchangeFee}(msg.sender, amount, extra), "Exchange inscription failed");

    SInscription memory inscription = getInscriptionByAmount(amount, address(this));

    require(inscription.extra != 0, "Incorrect inscription");

    require(ITruffi(token).transfer(msg.sender, amount.toDec(decimals) - 1), "Transfer back big amount failed");
    require(ITruffi(token).transfer(msg.sender, 1), "Transfer back small amount failed");

    collected[index][msg.sender].push(SCollected(block.number, slot, inscription));
    collectors[index][slot].push(msg.sender);
    emit OnCollect(msg.sender, index, slot, inscription);
    return true;
  }

  function getParticipants(uint index) external view returns(address[] memory) { return events[index].participants; }

  function getMeta(uint index) external view returns(string memory) {
    require(index < total, "Incorrect event index");
    SEvent memory data = events[index];
    bytes memory str = abi.encodePacked(
      "\"index\": ", data.index.toString(),
      ", \"start\": ", data.start.toString(),
      ", \"end\": ", data.end.toString(),
      ", \"seed\": ", "\"", data.seed.toString(), "\"",
      ", \"slots\": ", data.slots.toString(),
      ", \"prize\": ", data.prize.toString(),
      ", \"level\": ", data.level.toString()
    );
    return string(abi.encodePacked("{", str, "}"));
  }

  function getRequirements(uint index, uint participant) external view returns (SInscription[] memory) {
    require(index < total, "Incorrect event index");
    require(participant < events[index].participants.length, "Can not get requirements of the participant that does not exist");

    SEvent memory data = events[index];
    SRand memory rand = SRand(uint(keccak256(abi.encodePacked(data.seed, data.participants[participant]))), participant);
    SInscription[] memory ins = new SInscription[](data.slots);

    for(uint i = 0; i < data.slots; i++){
      ins[i] = SInscription(thresholds[data.level] + i, rand.num(), data.participants[participant]);
    }

    return ins;
  }

  function getCollectors(uint index, uint slot) external view returns (address[] memory) { return collectors[index][slot]; }

  function getCollected(uint index, address collector) external view returns (SCollected[] memory) { return collected[index][collector]; }

  function checkLastEventIsEnded() internal view returns(bool){
    if(total == 0) return true;
    if(block.number > events[total - 1].end) return true;
    return false;
  }

  function getInscriptionByAmount(uint amount, address addr) internal view returns (SInscription memory) {
    uint count = ITruffi(token).inscriptionCount(addr);
    SInscription memory inscription;

    for(uint i = 0; i < count; i++){
      inscription = ITruffi(token).inscriptionOfOwnerByIndex(addr, i);
      if(inscription.seed == amount) return inscription;
    }

    return inscription;
  }

}
