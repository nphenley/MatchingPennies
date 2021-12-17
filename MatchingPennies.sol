// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract MatchingPennies {
    
    struct Game{                    //struct encapsulating each instance of a game
                   
        bytes32 hash1;              //player1's hash
        bytes32 hash2;              //player2's hash
        
        uint lockedDeposit;        //funds reserved for winner
        
        uint verifiedNumber1;    //verified numbers updated when the initial hash has been matched with the number
        uint verifiedNumber2;
        
        uint invitationTimestamp;   //timestamp set after player 1 invites player 2 to a game. To prevent player 1's ether from being locked in the contract indefinitely if player 2 doesn't respond
        uint revealTimestamp;       //timestamp set after the first number is verified. There is a time limit preventing the game from going on forever. Whoever hasn't verified their number loses
        
        address player2; 
        address winner;
        
    }
    
    mapping(address => Game) ongoingGames;  //mapping to structs game structs using player 1's address
    mapping(address => bool) player1s;  //used to track game creators

    //@dev players enter their hashes. One either creates a new game if they have no ongoing one or joins the one they've been invited to
    //@param _otherPlayerAddress address that's been invited (from player 1) or player 1's address for player 2
    //@param _hash hash of a keccak256'd integer, need to add "0x" to the front
    function initialHash(address _otherPlayerAddress, bytes32 _hash) public payable {
        require(_otherPlayerAddress != msg.sender);                                     //can't invite yourself
        require(msg.value == 1 ether, "You can only send 1 Ether");
        require(player1s[msg.sender] == false, "You already have an ongoing game");     //this implementation only allows you to create 1 game at a time. You can be invited to play several times however
  
        if (player1s[_otherPlayerAddress]){                                             //for player 2 
           Game storage game = ongoingGames[_otherPlayerAddress];
           require(game.lockedDeposit == 1 ether, "Already deposited");                 //should already be 1 ether from player 1
           game.hash2 = _hash;
           game.lockedDeposit += msg.value;                                             //1 ether deposit
           
        }
          
        else {
            Game storage game = ongoingGames[msg.sender];                               //game is created if it doesn't exist yet
            game.player2 = _otherPlayerAddress;
            game.hash1 = _hash;
            player1s[msg.sender] = true;
            game.invitationTimestamp = block.timestamp;
            game.lockedDeposit += msg.value;
            
        }  
    }
    
    //@dev players enter their original, unhashed numbers and the contract checks their honesty
    //@param _player1 game creator address to point to game struct
    //@param _number unhashed number
    function originalNumbers(address _player1, string memory _number) public {
        require(player1s[_player1] == true);
        require(ongoingGames[_player1].lockedDeposit == 2 ether);
        bytes32 hashedNumber = keccak256(abi.encodePacked(_number));            //cheapest gas-wise hash function in solidity
        
        Game storage game = ongoingGames[_player1];
        
        if(msg.sender == _player1){                                             //player 1's number
            
            if (hashedNumber == game.hash1){
                game.verifiedNumber1 = st2num(_number);                         //converted to uint because keccak256 takes in strings not ints
                                    //0 or 1 for even or odd
            }
        }
        else {
                                                                                //player 2's number
            if (hashedNumber == game.hash2){
                game.verifiedNumber2 = st2num(_number);
                                           //could automatically disqualify if player puts in a wrong number
            }
        }
        
        if((game.verifiedNumber1 > 0) && (game.verifiedNumber2 > 0) ){          //if both players have verified their numbers we determine the winner
            uint finalValue1 = game.verifiedNumber1 % 2;
            uint finalValue2 = game.verifiedNumber2 % 2;                        //saving gas by not storing final values in the struct
            if(finalValue1 == finalValue2){
                game.winner = _player1;
            }
            else {
                game.winner = game.player2;
            }
        } 
        else {
            game.revealTimestamp = block.timestamp;     //once the first player to reveal their number does so, a timer starts (currently 2mins). If the other player doesn't verify theirs, they lose
        }
        
    }
    
    
    //@dev function to access all the information about a game
    //@param _player1Address game creator address to point to game struct
    function getGame(address _player1Address) view public returns (address, bytes32, bytes32, address, uint, uint, uint, uint, uint) {
        require(player1s[_player1Address], "Game doesn't exist");
        Game storage game = ongoingGames[_player1Address];
        return (game.player2, game.hash1, game.hash2, game.winner, game.lockedDeposit, game.verifiedNumber1, game.verifiedNumber2, game.invitationTimestamp, game.revealTimestamp);
    }
    
    //@dev function to convert string to uint, credit to GGizmos https://stackoverflow.com/questions/68976364/solidity-converting-number-strings-to-numbers
    //@param numString string to be converted to uint
    function st2num(string memory numString) private pure returns(uint) {
        uint  val=0;
        bytes   memory stringBytes = bytes(numString);
        for (uint  i =  0; i<stringBytes.length; i++) {
            uint exp = stringBytes.length - i;
            bytes1 ival = stringBytes[i];                   
            uint8 uval = uint8(ival);
           uint jval = uval - uint(0x30);
   
           val +=  (uint(jval) * (10**(exp-1))); 
        }
      return val;
    }
    
    //@dev function for the winner of the game to withdraw 
    //@param _player1 game creator address to point to game struct
    function winnerWithdraw(address _player1) public payable {
        require(player1s[_player1] == true, "Non-existent or finished game");
        
        if((_player1 == msg.sender) && (block.timestamp > ongoingGames[_player1].invitationTimestamp + 10 minutes) && ongoingGames[_player1].hash2 == 0){  //if player 2 hasn't responded to the invitation
            ongoingGames[_player1].winner = msg.sender;
        }
        
        if(block.timestamp > ongoingGames[_player1].revealTimestamp + 2 minutes){
            if((msg.sender == _player1) && (ongoingGames[_player1].verifiedNumber1 != 0) && (ongoingGames[_player1].verifiedNumber2 == 0)){             //if a player hasn't verifed their number
                ongoingGames[_player1].winner = msg.sender;
            }
            if((msg.sender == ongoingGames[_player1].player2) && (ongoingGames[_player1].verifiedNumber2 != 0) && (ongoingGames[_player1].verifiedNumber1 == 0)){
                ongoingGames[_player1].winner = msg.sender;
            }
        }
        require(ongoingGames[_player1].winner == msg.sender, "You are not the winner");
        
        uint amount = ongoingGames[_player1].lockedDeposit;
        delete ongoingGames[_player1];              //game information reset when winner withdraws
        player1s[_player1] = false;
        payable(msg.sender).transfer(amount);
   
    }
    
    function ts() view public returns (uint){
        return block.timestamp;
    }

    
}