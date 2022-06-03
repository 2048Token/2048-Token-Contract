// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Proof2048lib.sol";


contract Crypto2048Everest is Initializable, AccessControlUpgradeable {
    
    IERC20Upgradeable public Crypto2048Token;
    using SafeMathUpgradeable for uint;

    bytes32 public constant AMBASSADOR_ROLE = keccak256("AMBASSADOR_ROLE");

    struct Player {
        address playerAddress;
        bytes32 playerName;
        uint bestScore;
        uint level;
        uint joinedAt;
        bool isActivated;
    }
    Player[] public playersList;    

    struct GameSession {
    address playerAddress;
    uint sessionStartAt;
    uint sessionEndAt;
    uint[16] endGrid;
    uint confirmedScore;
    uint level;
    uint numMove;
    }
    GameSession[] public gameSessions;

    mapping(address => uint) public totalReward;
    mapping(address => uint) public claimedReward;
    mapping(address => uint) public rewardBalance;

    mapping(address => address) public referrer; //map playerAddress to their unique referrer address
    mapping(address => address[]) public referrals; //map referrer address to his/her referrals array
    
    mapping(address => uint) public ambasTotalReward;
    mapping(address => uint) public ambasClaimedReward;
    mapping(address => uint) public ambasRewardBalance;
    
    //event PlayerDeactivated(address indexed from, uint timestamp, string myString);
    event SessionStarted(address indexed from, uint timestamp, uint[16] endGrid, uint confirmedScore);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _Crypto2048Token) initializer public { 
        Crypto2048Token = IERC20Upgradeable(_Crypto2048Token);
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    ////////////Section 2: Add and Manage Players 
    //to play you need to deposit a small amount (0.001) ether to activate the account
    function addPlayer(string memory _name, address _referrer) external payable returns (bool) {
        //require(msg.value == 0.001 ether, "Only 0.001 Ether"); //require ether to activate an account
        require(Proof2048lib.getStrLen(_name) < 30 && Proof2048lib.getStrLen(_name) != 0, "Name must be >0 and <30 char"); // require playname less than 30 characters; UTF-8 requires multiple bytes to encode international characters.
        require(!checkIfPlayerExist(msg.sender), "Address already exists"); //require msg.send not in players array yet; 
        //require(!checkIfPlayerNameTaken(Proof2048lib.stringToBytes32(_name)), "Player name is already taken"); //disabled due to overhead; require player name is not taken by any other player yet

        //setReferrer(_referrer); player can use own address as referrer; for early access users, this is fine; to close this loophole in the future;
        require(referrer[_referrer] != msg.sender, "Mutual referral no allowed");
        referrer[msg.sender] = _referrer;
        referrals[_referrer].push(msg.sender);
        _setupRole(AMBASSADOR_ROLE, _referrer); //Ambas doesn't need to be an active player

        //add player to players array and initialize struct
        playersList.push(Player(msg.sender, Proof2048lib.stringToBytes32(_name), 0, 0, block.timestamp, true)); // can iterate over playerList array to get stats; this overlaps with mapping a bit in terms of functionality

        //initialize the first grid right after adding players so that players don't need to start a new session again
        //must convert default uint8 array to uint
        gameSessions.push(GameSession(msg.sender, block.timestamp, block.timestamp, [uint(0),2,0,0,0,0,0,0,0,0,0,0,0,0,0,0], 0, 0, 0)); // one address can have many game sessions (so not using mapping here)

        return true;
    }

    function getCurrentPlayer (address _addr) external view returns (Player memory) { 
        require(checkIfPlayerExist(_addr), "Player doesn't exist");
        uint len = playersList.length;
        Player memory n;
        if (len != 0 ) {
            for (uint i = 0; i < len; i++ ) {  
                if (playersList[i].playerAddress == _addr)  {
                    n = playersList[i];
                }
            }
        }
        return n;
    }

     //check if msg.sender in players[] already
    function checkIfPlayerExist(address _addr) internal view returns (bool) {
        uint len = playersList.length;
        if (len != 0 ) {
            for (uint i = 0; i < len; i++ ) {  //for loop to determine if player address exists or not
                if (playersList[i].playerAddress == _addr)  {
                    return true;
                }
            }
            return false;
        }
        else {
            return false;
        }
    }

    //check if player name is taken or not
    /* function checkIfPlayerNameTaken(bytes32 _playerName) internal view returns (bool) {
        uint len = playersList.length;
        if (len != 0 ) {
            for (uint i = 0; i < len; i++ ) {  //for loop to determine if player address exists or not
                if ( playersList[i].playerName == _playerName )  {
                    return true;
                }
            }
            return false;
        }
        else {
            return false;
        }
    } */

     function getPlayerActiveStatus (address _addr) public view returns (bool) {
        //require(checkIfPlayerExist(_addr), "player doesn't exist");
        return playersList[findPlayerIndex(_addr)].isActivated;
    }

    function isAmbassador (address _addr) public view returns (bool) {
        return hasRole(AMBASSADOR_ROLE, _addr);     
    }

    modifier onlyActivePlayer {
        require (getPlayerActiveStatus(msg.sender), "Not active player");
        _;      
    }


    // Only owner (to upgrade to roles in the future) can deactivate players if fraud is suspected
    function activatePlayer(address _addr) external onlyRole(DEFAULT_ADMIN_ROLE){
        playersList[findPlayerIndex(_addr)].isActivated = true;
    }

    // Only internal function can call this when fraud is detected
    function deactivatePlayer(address _addr) internal{
        //playerMap[_addr].isActivated = false;  //mapping is reference, cannot be directly updated; use playersList array to access struct
        playersList[findPlayerIndex(_addr)].isActivated = false; 
    }

    ////////////Section 3 Upload scores

    function submit(uint _score, uint[16] calldata _endGrid, uint _numMove) external onlyActivePlayer { //only active player can submit scores
        require(_score <= 3932104 && _score >0, "Score not right" ); //max score possible when there are 15 4's at the right time and all other tiles are 2's
        require(_endGrid.length == 16, "Board must have 16 tiles");

        //require elements in grid to be among [0,2,4,8,......,131072]; temporarily removed to shrink contract size
        /* if (Proof2048lib.ifTileIsPowerOfTwo(_endGrid) == false ){ 
            deactivatePlayer(msg.sender);
        } */

        uint currentSessionIndex = findSessionIndex();

        //Use findCurrentSessionIndex() to Find the current session index for msg.sender; update the new game session sessionEndAt and endGrid values
        //session must have started within the past 3600 seconds;
        require(gameSessions[currentSessionIndex].sessionStartAt + 3600 seconds >= block.timestamp, "Session has expired");
        // update the current session
        gameSessions[currentSessionIndex].sessionEndAt = block.timestamp;
        uint _totalSessionTime = totalSessionTime(); // for game verification
 
        //ending update session data
        
        uint playerIndex = findPlayerIndex(msg.sender);
        uint currentBestScore = playersList[playerIndex].bestScore;
        uint _totalNumMoves = totalNumMoves() + _numMove; //

        //Score verification
        bool verifiedOrNot = Proof2048lib.verifyScore(_score, _endGrid, _totalNumMoves, _totalSessionTime);
        if (verifiedOrNot){ //if verified and score is best, update player[msg.sender].bestScore and gameSession confirmed score; 
            
            gameSessions[currentSessionIndex].numMove = _numMove;
            gameSessions[currentSessionIndex].endGrid = _endGrid; //should we only save the new grid and score if it is better?
            gameSessions[currentSessionIndex].confirmedScore = _score;
            
            updateRewardBalance();
            //ambasUpdateRewardBalance();

            if (_score > currentBestScore) {
                //playerMap[msg.sender].bestScore = _score; //playerMap[msg.sender].bestScore = _score; this is not updating the struct property since mapping is just a reference; good for view, but not good for update
                playersList[playerIndex].bestScore = _score; // find the exact location of the struct in the array and update its property
                setLevel(msg.sender, _endGrid);
            }

        } else {  //if not verified; must be fraud. deactivate the player for now
            deactivatePlayer(msg.sender);
            //emit PlayerDeactivated(msg.sender, block.timestamp, "Deactivated");
        }
    }

    function findPlayerIndex(address _addr) internal view returns (uint){
        require(checkIfPlayerExist(_addr), "Player not exist"); //require msg.sender in playersList array
        uint len = playersList.length;
        uint playerIndex; 
        for (uint i = 0; i < len; i++ ) {
            if (_addr == playersList[i].playerAddress){
                playerIndex = i; 
            }
        }    
        return playerIndex;
    }

    //Sessions: find msg.sender's current session index
    function findSessionIndex() internal view returns (uint){
        uint len = gameSessions.length;
        uint sessionIndex = 0;
        if (len != 0 ) { //this is always true as a first session was created when adding a new player
            for (uint i = 0; i <= len-1; i++ ) { //next time try starting with the furthest to save computing; i-- can get to minus 1, so i needs to be signed integer
                if (gameSessions[i].playerAddress == msg.sender){ 
                    sessionIndex = i; //find the latest session owned by the msg.sender
                }
            }
        }
        return sessionIndex;
    }

    function startSession () external onlyActivePlayer {
        //find the last session index of player msg.sender
        uint lastSessionIndex = findSessionIndex(); //find the last session owned by the msg.sender     
        //check if the last session ended or not
        require(gameSessions[lastSessionIndex].sessionStartAt + 3600 seconds <= block.timestamp, "Session not ended");
        //if the previous session has ended, start a new session
        gameSessions.push(GameSession(msg.sender, block.timestamp,block.timestamp,gameSessions[lastSessionIndex].endGrid, gameSessions[lastSessionIndex].confirmedScore, gameSessions[lastSessionIndex].level, 0)); //retrieve last session data for a new session; need to update when the player submit score for this session; 
        //return gameSessions[lastSessionIndex].endGrid; //return the previous session endGrid to Dapp frontend; this only work for "view" 
        emit SessionStarted(msg.sender, block.timestamp, gameSessions[lastSessionIndex].endGrid, gameSessions[lastSessionIndex].confirmedScore); 
    }

    function getCurrentSession () external view onlyActivePlayer returns (GameSession memory) {
        uint index = findSessionIndex();
        require(gameSessions[index].sessionStartAt + 3600 seconds >= block.timestamp, "No current session");
        return gameSessions[index];
    }

    function hasCurrSession () external view onlyActivePlayer returns (bool) {
        uint i = findSessionIndex();
        if (block.timestamp - gameSessions[i].sessionStartAt < 3600 seconds){
            return true;
        } else {
            return false;
        }

    }

    ///////////Section 4, Level and Score verification
    function totalNumMoves () public view returns (uint) {
        uint len = gameSessions.length;
        uint total = 0;
        if (len != 0 ) { //this is always true as a first session was created when adding a new player
            for (uint i = 0; i < len; i++ ) { 
                if (gameSessions[i].playerAddress == msg.sender){
                    total = total.add(gameSessions[i].numMove) ;
                }
            }
        }
        return total;
    }

    function totalSessionTime () public view returns (uint) {
        uint len = gameSessions.length;
        uint total = 0;
        if (len != 0 ) { //this is always true as a first session was created when adding a new player
            for (uint i = 0; i < len; i++ ) { 
                if (gameSessions[i].playerAddress == msg.sender){
                    uint sessionTime = gameSessions[i].sessionEndAt.sub(gameSessions[i].sessionStartAt); //if a session was started but never submitted, it won't count as beginAt = endAt. 
                    total = total.add(sessionTime); //sessionTime is in seconds
                }
            }
        }
        return total;
    }

    function setLevel (address _address, uint[16] calldata _endGrid) internal { //set level for msg.sender
        uint maxTile = Proof2048lib.getMaxTile(_endGrid);
        uint playerIndex = findPlayerIndex(_address);
        uint currentSessionIndex = findSessionIndex();
        if (maxTile < 2048 ) {
            playersList[playerIndex].level = 0;
            gameSessions[currentSessionIndex].level =0;
        } else if (maxTile == 2048) {
            playersList[playerIndex].level = 1;
            gameSessions[currentSessionIndex].level =1;
        } else if (maxTile == 4096){
            playersList[playerIndex].level = 2;
            gameSessions[currentSessionIndex].level =2;
        } else if (maxTile == 8192){
            playersList[playerIndex].level = 3;
            gameSessions[currentSessionIndex].level =3;
        } else if (maxTile == 16384){
            playersList[playerIndex].level = 4;
            gameSessions[currentSessionIndex].level =4;
        } else if (maxTile == 32768){
            playersList[playerIndex].level = 5;
            gameSessions[currentSessionIndex].level =5;
        } else if (maxTile == 65536){
            playersList[playerIndex].level = 6;
            gameSessions[currentSessionIndex].level =6;
        } else if (maxTile == 131072){
            playersList[playerIndex].level = 7;
            gameSessions[currentSessionIndex].level =7;
        } else { // save bytecode size
        }
    } 

    //////////Section 5, Reward based on level and session time on that level;
    function calTotalRewardCMG(address _addr) public view onlyActivePlayer returns (uint) {
        uint rps = 0; //reward per second
        uint total = 0;
    
        uint len = gameSessions.length;
        if (len != 0 ) { //this is always true as a first session was created when adding a new player
            for (uint i = 0; i < len; i++ ) { 
                if (gameSessions[i].playerAddress == _addr){
                    uint level = gameSessions[i].level;
                    if (level == 0) {
                        rps = 10 ** 13;
                    } else if (level == 1) {
                        rps = 5 * (10 ** 13);
                    } else if (level == 2){
                        rps = 10 ** 14;
                    } else if (level == 3){
                        rps = 2 * (10 ** 14);
                    } else if (level == 4){
                        rps = 4 * (10 ** 14);
                    } else if (level == 5){
                        rps = 8 * (10 ** 14);
                    } else if (level == 6){
                        rps = 32 * (10 ** 14);
                    } else if (level == 7){
                        rps = 16 * (10 ** 15);
                    } else {
                        rps = 0;
                    }
                    uint sessionTime = gameSessions[i].sessionEndAt.sub(gameSessions[i].sessionStartAt); //if a session was started but never submitted, it won't count as beginAt = endAt. 
                    total = total.add(sessionTime.mul(rps)); //sessionTime is in seconds
                }
            }
        }
        return total;
    }

    function updateRewardBalance () public {
        if (getPlayerActiveStatus(msg.sender)){
            totalReward[msg.sender] = calTotalRewardCMG(msg.sender);
            rewardBalance[msg.sender] = totalReward[msg.sender].sub(claimedReward[msg.sender]);  //return totalReward[msg.sender]; //you cannot return a mapping! just use the public getter! https://vomtom.at/how-to-return-a-mapping-in-solidity-and-web3/
        }
        //reward to ambassador; onlyAmbas; need to check if msg.sender has a referrer first!!!
        uint len = referrals[referrer[msg.sender]].length;
        uint total = 0;
        for (uint i=0; i < len; i++) { //calculate Ambassador total reward CMG based on referrals' total rewards
            total = total + calTotalRewardCMG(referrals[referrer[msg.sender]][i]);
        }
        ambasTotalReward[referrer[msg.sender]] = total.div(20); // 5% referral commission
        ambasRewardBalance[referrer[msg.sender]] = ambasTotalReward[referrer[msg.sender]].sub(ambasClaimedReward[referrer[msg.sender]]);
        
    }

    function claimReward () public onlyActivePlayer {
        uint currentClaim = rewardBalance[msg.sender];
        require(currentClaim <= Crypto2048Token.balanceOf(address(this)) && currentClaim >0, "not enough CMG");
        claimedReward[msg.sender] = claimedReward[msg.sender].add(currentClaim); 
        rewardBalance[msg.sender] = 0; // Remember to zero the pending refund before sending to prevent re-entrancy attacks
        Crypto2048Token.transfer(msg.sender, currentClaim);
    }

    function ambasClaimReward () public {
        if (isAmbassador(msg.sender)){
            uint currentClaim = ambasRewardBalance[msg.sender];
            require(currentClaim <= Crypto2048Token.balanceOf(address(this)) && currentClaim >0, "not enough CMG");
            ambasClaimedReward[msg.sender] = ambasClaimedReward[msg.sender].add(currentClaim); 
            ambasRewardBalance[msg.sender] = 0; // Remember to zero the pending refund before sending to prevent re-entrancy attacks
            Crypto2048Token.transfer(msg.sender, currentClaim);
        }
    }

}