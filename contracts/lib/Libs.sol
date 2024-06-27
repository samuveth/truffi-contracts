// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";

struct SInscription { uint seed; uint extra; address creator; }
struct SRand { uint seed; uint nonce; }
struct SRandInc { uint seed; uint nonce; uint extra; bool isSpecial; }
struct SMeta { uint skyType; uint skyColor; uint horizonType; uint horizonColor; uint groundType; uint groundColor; uint faceType; uint stemType; uint stemColor; uint capType; uint capColor; uint dotsColor; bool isSpecial; address creator; }

library RandLib {
  function num(SRand memory rand) internal pure returns (uint) { return uint(keccak256(abi.encodePacked(rand.seed + rand.nonce++ - 1))); }

  function next(SRandInc memory rand) internal pure returns (uint) {
    return uint(keccak256(abi.encodePacked(rand.isSpecial, rand.seed + rand.nonce++ - 1, rand.extra)));
  }

  function chances(uint seed, bool isSpecial) internal pure returns (uint16[4] memory){
    uint16[4] memory thresholds = [300, 1200, 2100, 3000];
		uint16[4][6] memory tears = [[3164, 492, 61, 6], [4011, 805, 115, 16], [4902, 1183, 182, 24], [5718, 1553, 252, 31], [6296, 1798, 302, 37], [8000, 6000, 4000, 2000]];
    if (isSpecial) return tears[5];
    if (seed < thresholds[0]) return tears[0];
    if (seed < thresholds[1]) return tears[1];
    if (seed < thresholds[2]) return tears[2];
    if (seed < thresholds[3]) return tears[3];
    return tears[4];
  }

  function lvl(SRandInc memory rand) internal pure returns (uint) {
    uint chance = next(rand) % 10000;
    if (chance < chances(rand.seed, rand.isSpecial)[3]) return 4;
    if (chance < chances(rand.seed, rand.isSpecial)[2]) return 3;
    if (chance < chances(rand.seed, rand.isSpecial)[1]) return 2;
    if (chance < chances(rand.seed, rand.isSpecial)[0]) return 1;
    return 0;
  }
}

library DecimalsLib {
  function toDec(uint value, uint dec) internal pure returns (uint) { return value * 10 ** dec; }
}

library MetaLib {
  using Strings for uint;
  using Strings for address;
  using RandLib for SRandInc;

  function meta(SMeta memory md) internal pure returns (string memory) {
    bytes memory str = abi.encodePacked("\"skyColor\": ", md.skyColor.toString(), ", \"skyType\": ", md.skyType.toString(), ", \"horizonType\": ", (md.horizonType).toString());
    str = abi.encodePacked(str, ", \"horizonColor\": ", md.horizonColor.toString(), ", \"groundType\": ", (md.groundType).toString(), ", \"groundColor\": ", md.groundColor.toString());
    str = abi.encodePacked(str, ", \"faceType\": ", (md.faceType).toString(), ", \"stemType\": ", (md.stemType).toString(), ", \"stemColor\": ", md.stemColor.toString());
    str = abi.encodePacked(str, ", \"capType\": ", (md.capType).toString(), ", \"capColor\": ", md.capColor.toString());
    str = md.capColor != md.dotsColor ? abi.encodePacked(str, ", \"dotsColor\": ", md.dotsColor.toString()) : str;
    str = abi.encodePacked(str, ", \"isSpecial\": ", md.isSpecial ? "true" : "false", ", \"address\": \"", md.creator.toHexString(), "\"");
    return string(abi.encodePacked("{", str, "}"));
  }

  function data(SInscription memory inscription, address special) internal pure returns (SMeta memory){
    SMeta memory md;
    uint colors = 10;

    SRandInc memory rand = SRandInc(inscription.seed, 0, inscription.extra, inscription.creator == special);

    md.skyType = rand.lvl();
    md.skyColor = rand.next() % colors;
    md.horizonType = rand.lvl();
    md.horizonColor = rand.next() % colors;
    md.groundType = rand.lvl();
    md.groundColor = rand.next() % colors;
    md.faceType = rand.lvl();
    md.stemType = rand.lvl();
    md.stemColor = rand.next() % colors;
    md.capType = rand.lvl();
    md.capColor = rand.next() % colors;
    md.dotsColor = rand.lvl() > 1 ? rand.next() % colors : md.capColor;
    md.isSpecial = inscription.creator == special;
    md.creator = inscription.creator;

    return md;
  }
}
