// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Libs.sol";
import "./lib/Ownable.sol";

struct SScore { address user; uint score; }
struct SRange { uint index; uint min; uint max; }
struct SWinner { uint index; address winner; uint position; uint number; }

contract Winners is Ownable {
  using RandLib for SRand;

  mapping(uint => SWinner) public winner;
  mapping(uint => mapping(uint => SScore)) public score;
  mapping(uint => mapping(uint => SRange)) public range;
  mapping(uint => uint) public total;

  event OnWin(SWinner winner);

  constructor() {}

  function setScoresAndGetWinner(uint index, SScore[] calldata arr) external onlyOwner returns (SWinner memory){
    require(winner[index].winner == address(0), "Winner is already set for this events index");

    total[index] = arr.length;
    
    uint count = 0;
    uint min = 0;

    for(uint i = 0; i < total[index]; i++){
      min = count;
      count = count + arr[i].score;
      range[index][i] = SRange(i, min, count - 1);
      score[index][i] = SScore(arr[i].user, arr[i].score);
    }

    SRand memory rand = SRand(uint(keccak256(abi.encodePacked(count, block.prevrandao))), total[index]);
    uint number = rand.num() % count;

    uint position;

    for(uint i = 0; i < total[index]; i++){
      if(number >= range[index][i].min && number <= range[index][i].max){
        position = i;
        break;
      }
    }

    winner[index] = SWinner(index, score[index][position].user, position, number);
    emit OnWin(winner[index]);
    return winner[index];
  }

}