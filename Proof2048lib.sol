// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @custom:security-contact support@2048token.com

library Proof2048lib {

    function ifTileIsPowerOfTwo (uint256[16] calldata _endGrid) internal pure returns (bool) {
        uint256[18] memory tiles = [uint256(0),2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536,131072];
        uint256 count = 0; 
        for (uint256 i = 0; i < 16; i++ ){
            for (uint256 j = 0; j < 18; j++ ){
                if (_endGrid[i] == tiles[j] ) {count = count +1 ;}
            }
            if (count == 0){return false;} //_endGrid[i] is not among the 18 tiles
            count = 0; //reset count back to 0 and move to the next 
        }
        return true;
    }

    //get the string length via bytes().length method (string.length does not exist in solidity)
    function getStrLen (string memory str) internal pure returns (uint256) {
        return bytes(str).length;
    }

    function stringToBytes32(string memory _source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(_source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(_source, 32))
        }
    }

    function log_2(uint256 _tile) internal pure returns (uint256){
       // uint256[17] tiles = [uint256(2),4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536,131072];
        uint256 j = 0; 
        require (_tile != 0, "Logarithm not accepting 0");
        for (uint256 i = 1; i <= 17; i++ ) { 
           if (_tile == 2**i) {
                j = i;
           }       
        }
        return j;
    }

    function verifyScore(uint256 _score, uint256[16] calldata _endGrid, uint256 _totalNumMoves, uint256 _totalSessionTime) internal pure returns (bool) {
        uint256 maxScore = 0; // maxmium score possible with _endGrid
        uint256 maxTile = getMaxTile(_endGrid); // the largest tile on the _endGrid
        uint256 minTotalTime; // minimal total time required to achieve the maxTile
        uint256 minNumMoves; // minimal num of moves required to achieve the maxTile

        //1. check submitted _score vs max score possible for the endGrid
        for (uint256 i = 0; i < 16; i++ ) { 
           if (_endGrid[i] != 0) { //only taking non-zero tiles 
                uint256 n = log_2(_endGrid[i]);
                maxScore = maxScore + (n-1)*(2**n);
           }
        }
        
        //2. _totalSessionTime should exceed minimally required time for human based on the maxTile achieved
        if (maxTile > 2048) {
            minTotalTime = maxTile / 3;
            minNumMoves = maxTile / 2;
        } else if (maxTile >= 1024 && maxTile <= 2048) {
            minTotalTime = maxTile / 4;
            minNumMoves = maxTile / 3;
        } else {
            minTotalTime = 0;
            minNumMoves = 0;
        }

        //3. check _totalNumMoves / _totalSessionTime is over human limit
        uint256 moveSpeed = _totalNumMoves / _totalSessionTime;

        // summarize
        if (_score <= maxScore && _totalSessionTime >= minTotalTime && _totalNumMoves >= minNumMoves && moveSpeed <= 4 ) {return true;}
        else { return false; }
    }

    function getMaxTile (uint256[16] calldata _endGrid) internal pure returns (uint256) { //set level for msg.sender
        //require elements in grid to be among [0,2,4,8,......,131072]
        uint256 maxTile = 0;
        uint256 i = 0;
        for(i=0; i<16; i++) { //find the largest tile on _endGrid array
            if(maxTile < _endGrid[i]){
               maxTile = _endGrid[i];  //pass the larger one to maxTile
            }
        }
        return maxTile;
    }

}
