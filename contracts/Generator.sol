// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./lib/Ownable.sol";

uint8 constant colorsCount = 10;
address constant special = 0x07339c13953afAD77B783E1e783f7bbA94Bb8677;
string constant description = "Random Token Generator";
string constant web = "https://random.art/";

struct MushroomData {
	uint skyType;
	uint skyColor;
	uint horizonType;
	uint horizonColor;
	uint groundType;
	uint groundColor;
	uint faceType;
	uint stemType;
	uint stemColor;
	uint capType;
	uint capColor;
	uint dotsColor;
	bool isSpecial;
}

struct SeedData {
	uint seed;
	uint extra;
	address creator;
}
struct Rand {
	uint seed;
	uint nonce;
	uint extra;
	bool isSpecial;
}

library RandLib {
	function next(Rand memory rnd) internal pure returns (uint) {
		return uint(keccak256(abi.encodePacked(rnd.isSpecial, rnd.seed + rnd.nonce++ - 1, rnd.extra)));
	}

	function chances(uint seed, bool isSpecial) internal pure returns (uint16[4] memory) {
		uint16[4] memory thresholds = [300, 1200, 2100, 3000];
		uint16[4][6] memory tears = [[3164, 492, 61, 6], [4011, 805, 115, 16], [4902, 1183, 182, 24], [5718, 1553, 252, 31], [6296, 1798, 302, 37], [8000, 6000, 4000, 2000]];
		if (isSpecial) return tears[5];
		if (seed < thresholds[0]) return tears[0];
		if (seed < thresholds[1]) return tears[1];
		if (seed < thresholds[2]) return tears[2];
		if (seed < thresholds[3]) return tears[3];
		return tears[4];
	}

	function lvl(Rand memory rnd) internal pure returns (uint) {
		uint chance = next(rnd) % 10000;
		if (chance < chances(rnd.seed, rnd.isSpecial)[3]) return 4;
		if (chance < chances(rnd.seed, rnd.isSpecial)[2]) return 3;
		if (chance < chances(rnd.seed, rnd.isSpecial)[1]) return 2;
		if (chance < chances(rnd.seed, rnd.isSpecial)[0]) return 1;
		return 0;
	}
}

library StringLib {
	function toString(uint value) internal pure returns (string memory) {
		if (value == 0) return "0";
		uint temp = value;
		uint digits;
		while (temp != 0) {
			digits++;
			temp /= 10;
		}
		bytes memory buffer = new bytes(digits);
		while (value != 0) {
			digits -= 1;
			buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
			value /= 10;
		}
		return string(buffer);
	}
}

library MetaLib {
	using StringLib for uint;

	function meta(MushroomData memory data) internal pure returns (string memory) {
		bytes memory str = abi.encodePacked('"skyColor": ', data.skyColor.toString(), ', "skyType": ', data.skyType.toString(), ', "horizonType": ', (data.horizonType).toString());
		str = abi.encodePacked(str, ', "horizonColor": ', data.horizonColor.toString(), ', "groundType": ', (data.groundType).toString(), ', "groundColor": ', data.groundColor.toString());
		str = abi.encodePacked(str, ', "faceType": ', (data.faceType).toString(), ', "stemType": ', (data.stemType).toString(), ', "stemColor": ', data.stemColor.toString());
		str = abi.encodePacked(str, ', "capType": ', (data.capType).toString(), ', "capColor": ', data.capColor.toString(), ', "dotsColor": ', data.dotsColor.toString(), ', "isSpecial": ', data.isSpecial ? "true" : "false");
		return string(abi.encodePacked("{", str, "}"));
	}
}

contract Generator is Ownable {
	using RandLib for Rand;
	using MetaLib for MushroomData;
	using StringLib for uint;

	string[10][3] private colors;
	string[5][6] private backgrounds;
	string[6][5][7] private shapes;

	constructor() {}

	function setMushrooms(string[6][5] calldata data, uint origin) external onlyOwner returns (bool) {
		for (uint i = 0; i < 5; i++) {
			for (uint y = 0; y < 6; y++) {
				shapes[origin][i][y] = data[i][y];
			}
		}
		return true;
	}

	function setBackgrounds(string[5] calldata data, uint origin) external onlyOwner returns (bool) {
		for (uint i = 0; i < 5; i++) {
			backgrounds[origin][i] = data[i];
		}
		return true;
	}

	function setColors(string[10][3] calldata data) external onlyOwner returns (bool) {
		for (uint i = 0; i < 3; i++) {
			for (uint y = 0; y < 10; y++) {
				colors[i][y] = data[i][y];
			}
		}
		return true;
	}

	function getSvg(SeedData calldata seed_data) external view returns (string memory) {
		return toSvg(getData(seed_data), false);
	}

	function getAnimatedSvg(SeedData calldata seed_data) external view returns (string memory) {
		return toSvg(getData(seed_data), true);
	}

	function getMeta(SeedData calldata seed_data) external pure returns (string memory) {
		return getData(seed_data).meta();
	}

	function toSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		return string(abi.encodePacked("<svg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 220 220'>", "<def>", aniDef(ani), filterDef(), "</def>", mainSvg(data, ani), "</svg>"));
	}

	function getData(SeedData calldata seed_data) internal pure returns (MushroomData memory) {
		MushroomData memory data;
		data.isSpecial = seed_data.creator == special;
		Rand memory rnd = Rand(seed_data.seed, 0, seed_data.extra, data.isSpecial);
		data.skyType = rnd.lvl();
		data.skyColor = rnd.next() % colorsCount;
		data.horizonType = rnd.lvl();
		data.horizonColor = rnd.next() % colorsCount;
		data.groundType = rnd.lvl();
		data.groundColor = rnd.next() % colorsCount;
		data.faceType = rnd.lvl();
		data.stemType = rnd.lvl();
		data.stemColor = rnd.next() % colorsCount;
		data.capType = rnd.lvl();
		data.capColor = rnd.next() % colorsCount;
		data.dotsColor = rnd.lvl() > 1 ? rnd.next() % colorsCount : data.capColor;
		return data;
	}

	function mainSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bytes memory svgBackground = abi.encodePacked("<rect width='220' height='220' fill='white'/>", "<rect opacity='0.5' width='220' height='220' fill='", colors[0][data.skyColor], "'/>");
		bytes memory svgGrain = abi.encodePacked("<g><rect filter='url(#grains)' ", !ani ? "" : "transform='translate(-440, 0)'", " width='", uint(!ani ? 220 : 880).toString(), "' height='220' opacity='0.8'/>", transGen(30, ani), "</g>");
		bytes memory svgCombined = abi.encodePacked(skySvg(data, ani), horizonSvg(data, ani), groundSvg(data, ani), svgGrain);
		return string(abi.encodePacked("<g filter='url(#grains)'>", svgBackground, svgCombined, shroomSvg(data, ani), frontSvg(data, ani), "</g>"));
	}

	function skySvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bytes memory svgBox = abi.encodePacked("<rect opacity='0' width='", uint(!ani ? 220 : 880).toString(), "' height='220'/>");
		bytes memory svgSky = abi.encodePacked("<path d='", backgrounds[0][data.skyType], "' fill='white' />");
		svgSky = !ani ? svgSky : abi.encodePacked(svgSky, "<path transform='translate(-440, 0)' d='", backgrounds[0][data.skyType], "' fill='white' stroke='white'/>");
		return string(abi.encodePacked("<g>", svgBox, svgSky, transGen(60, ani), "</g>"));
	}

	function horizonSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bytes memory svgBox = abi.encodePacked("<rect opacity='0' width='", uint(!ani ? 220 : 880).toString(), "' height='220'/>");
		bytes memory svgBehind = abi.encodePacked("<path d='", backgrounds[1][data.horizonType], "' stroke-width='0.1' stroke='", colors[0][data.skyColor], "' fill='", colors[0][data.skyColor], "'/>");
		svgBehind = !ani ? svgBehind : abi.encodePacked(svgBehind, "<path transform='translate(-440, 0)' d='", backgrounds[1][data.horizonType], "' stroke-width='0.1' stroke='", colors[0][data.skyColor], "' fill='", colors[0][data.skyColor], "'/>");
		bytes memory svgMid = abi.encodePacked("<path opacity='0.75' d='", backgrounds[1][data.horizonType], "' stroke-width='0.1' stroke='", colors[0][data.horizonColor], "' fill='", colors[0][data.horizonColor], "'/>");
		svgMid = !ani ? svgMid : abi.encodePacked(svgMid, "<path transform='translate(-440, 0)' opacity='0.75' d='", backgrounds[1][data.horizonType], "' stroke-width='0.1' stroke='", colors[0][data.horizonColor], "' fill='", colors[0][data.horizonColor], "'/>");
		return string(abi.encodePacked("<g>", svgBox, svgBehind, svgMid, transGen(45, ani), "</g>"));
	}

	function groundSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bytes memory svgBox = abi.encodePacked("<rect opacity='0' width='", uint(!ani ? 220 : 880).toString(), "' height='220'/>");
		bytes memory svgGround = abi.encodePacked("<path d='", backgrounds[2][data.groundType], "' stroke='", colors[0][data.groundColor], "' fill='", colors[0][data.groundColor], "'/>");
		svgGround = !ani ? svgGround : abi.encodePacked(svgGround, "<path transform='translate(-440, 0)' d='", backgrounds[2][data.groundType], "' stroke='", colors[0][data.groundColor], "' fill='", colors[0][data.groundColor], "'/>");
		bytes memory svgDetails = abi.encodePacked("<path d='", backgrounds[3][data.groundType], "' fill='#383838' opacity='0.8' />");
		svgDetails = !ani ? svgDetails : abi.encodePacked(svgDetails, "<path transform='translate(-440, 0)' d='", backgrounds[3][data.groundType], "' fill='#383838' opacity='0.8' />");
		return string(abi.encodePacked("<g>", svgBox, svgGround, svgDetails, transGen(25, ani), "</g>"));
	}

	function shroomSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bool equal = data.capColor == data.dotsColor;
		bytes memory cap = abi.encodePacked("<path d='", shapes[0][data.capType][0], "' fill='", colors[1][data.capColor], "' stroke='black'>", aniGen(shapes[0][data.capType], ani), "</path>");
		cap = abi.encodePacked(cap, "<path d='", shapes[1][data.capType][0], "' fill='#383838' opacity='0.8'>", aniGen(shapes[1][data.capType], ani), "</path>");
		bytes memory capOn = abi.encodePacked("<path d='", shapes[2][data.capType][0], "' fill='", colors[1][data.dotsColor], "' stroke='black'>", aniGen(shapes[2][data.capType], ani), "</path>");
		capOn = abi.encodePacked(capOn, "<path d='", shapes[3][data.capType][0], "' fill='#383838' opacity='0.8'>", aniGen(shapes[3][data.capType], ani), "</path>");
		cap = abi.encodePacked(cap, equal ? bytes("") : capOn);
		bytes memory stem = abi.encodePacked("<path d='", shapes[4][data.stemType][0], "' fill='", colors[2][data.stemColor], "' stroke='black'>", aniGen(shapes[4][data.stemType], ani), "</path>");
		stem = abi.encodePacked(stem, "<path d='", shapes[5][data.stemType][0], "' fill='#383838' opacity='0.8'>", aniGen(shapes[5][data.stemType], ani), "</path>");
		stem = abi.encodePacked(stem, "<path d='", shapes[6][data.faceType][0], "' fill='black'>", aniGen(shapes[6][data.faceType], ani), "</path>");
		bytes memory transform = abi.encodePacked("transform='translate()'");
		return string(abi.encodePacked("<g ", transform, ">", cap, stem, "</g>"));
	}

	function frontSvg(MushroomData memory data, bool ani) private view returns (string memory) {
		bytes memory svgBox = abi.encodePacked("<rect opacity='0' width='", uint(!ani ? 220 : 880).toString(), "' height='220'/>");
		bytes memory svgFront = abi.encodePacked("<path d='", backgrounds[4][data.groundType], "' fill='", colors[0][data.skyColor], "'/>");
		svgFront = !ani ? svgFront : abi.encodePacked(svgFront, "<path transform='translate(-440, 0)' d='", backgrounds[4][data.groundType], "' fill='", colors[0][data.skyColor], "'/>");
		return string(abi.encodePacked("<g>", svgBox, svgFront, transGen(10, ani), "</g>"));
	}

	function aniDef(bool ani) private pure returns (string memory) {
		if (!ani) return "";
		string memory anim;
		for (uint i; i < 10; i++) {
			string memory begin = i < 1 ? "0;f10" : string(abi.encodePacked("f", i.toString()));
			anim = string(abi.encodePacked(anim, "<animate id='f", (i + 1).toString(), "' begin='", begin, ".end' dur='100ms'/>"));
		}
		return anim;
	}

	function filterDef() private pure returns (string memory) {
		return
			string(
				abi.encodePacked(
					"<filter id='grains'>",
					"<feTurbulence seed='12' type='fractalNoise' baseFrequency='15' numOctaves='1' result='turbulence' />",
					"<feComponentTransfer width='100%' height='100%' in='turbulence' result='componentTransfer'><feFuncA type='table' tableValues='0 0.35'/></feComponentTransfer>",
					"<feBlend in='SourceGraphic' mode='hue'/>",
					"</filter>"
				)
			);
	}

	function aniGen(string[6] memory values, bool ani) private pure returns (string memory) {
		if (!ani) return "";
		string memory anim;
		uint r = 0;
		for (uint i = 1; i <= 10; i++) {
			anim = string(abi.encodePacked(anim, "<animate begin='f", i.toString(), ".end' fill='freeze' attributeName='d' dur='300ms' to='", values[i - r], "'/>"));
			r = i < 5 ? 0 : r + 2;
		}
		return anim;
	}

	function transGen(uint8 dur, bool ani) private pure returns (string memory) {
		if (!ani) return "";
		return string(abi.encodePacked("<animateTransform begin='0' fill='freeze' attributeName='transform' type='translate' dur='", uint(dur).toString(), "s' from='0 0' to='440 0' repeatCount='indefinite'/>"));
	}
}
