// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {Swap} from "../contracts/Swap.sol";
import {DataTypes} from "../contracts/libraries/DataTypes.sol";
import {Events} from "../contracts/libraries/Events.sol";
import {MiraToken} from "../contracts/mocks/MiraToken.sol";
import {WCSB} from "../contracts/mocks/WCSB.sol";
import {EmitExpecter} from "./EmitExpecter.sol";
import {
    TransparentUpgradeableProxy
} from "../contracts/upgradeability/TransparentUpgradeableProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract SwapTest is Test, EmitExpecter {
    TransparentUpgradeableProxy public proxySwap;
    MiraToken mira;
    Swap swap;

    // bob owns CSB, he can sell CSB and accepts sell order of MIRA
    address public constant alice = address(0x1111);
    // alice owns MIRA, she can sell MIRA and accepts sell order of CSB
    address public constant bob = address(0x2222);
    address public constant admin = address(0x3333);
    address public constant proxyOwner = address(0x4444);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint8 public constant SELL_MIRA = 1;
    uint8 public constant SELL_CSB = 2;

    uint256 public constant MIN_MIRA = 100 ether;
    uint256 public constant MIN_CSB = 10 ether;
    uint256 public constant OPERATION_TYPE_ACCEPT_ORDER = 1;
    uint256 public constant OPERATION_TYPE_SELL_MIRA = 2;
    uint256 public constant INITIAL_MIRA_BALANCE = MIN_MIRA * 100;
    uint256 public constant INITIAL_CSB_BALANCE = MIN_CSB * 100;

    event Paused(address account);
    event Unpaused(address account);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Sent(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );

    function setUp() public {
        // deploy erc1820
        vm.etch(
            address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24),
            bytes( // solhint-disable-next-line max-line-length
                hex"608060405234801561001057600080fd5b50600436106100a5576000357c010000000000000000000000000000000000000000000000000000000090048063a41e7d5111610078578063a41e7d51146101d4578063aabbb8ca1461020a578063b705676514610236578063f712f3e814610280576100a5565b806329965a1d146100aa5780633d584063146100e25780635df8122f1461012457806365ba36c114610152575b600080fd5b6100e0600480360360608110156100c057600080fd5b50600160a060020a038135811691602081013591604090910135166102b6565b005b610108600480360360208110156100f857600080fd5b5035600160a060020a0316610570565b60408051600160a060020a039092168252519081900360200190f35b6100e06004803603604081101561013a57600080fd5b50600160a060020a03813581169160200135166105bc565b6101c26004803603602081101561016857600080fd5b81019060208101813564010000000081111561018357600080fd5b82018360208201111561019557600080fd5b803590602001918460018302840111640100000000831117156101b757600080fd5b5090925090506106b3565b60408051918252519081900360200190f35b6100e0600480360360408110156101ea57600080fd5b508035600160a060020a03169060200135600160e060020a0319166106ee565b6101086004803603604081101561022057600080fd5b50600160a060020a038135169060200135610778565b61026c6004803603604081101561024c57600080fd5b508035600160a060020a03169060200135600160e060020a0319166107ef565b604080519115158252519081900360200190f35b61026c6004803603604081101561029657600080fd5b508035600160a060020a03169060200135600160e060020a0319166108aa565b6000600160a060020a038416156102cd57836102cf565b335b9050336102db82610570565b600160a060020a031614610339576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b6103428361092a565b15610397576040805160e560020a62461bcd02815260206004820152601a60248201527f4d757374206e6f7420626520616e204552433136352068617368000000000000604482015290519081900360640190fd5b600160a060020a038216158015906103b85750600160a060020a0382163314155b156104ff5760405160200180807f455243313832305f4143434550545f4d4147494300000000000000000000000081525060140190506040516020818303038152906040528051906020012082600160a060020a031663249cb3fa85846040518363ffffffff167c01000000000000000000000000000000000000000000000000000000000281526004018083815260200182600160a060020a0316600160a060020a031681526020019250505060206040518083038186803b15801561047e57600080fd5b505afa158015610492573d6000803e3d6000fd5b505050506040513d60208110156104a857600080fd5b5051146104ff576040805160e560020a62461bcd02815260206004820181905260248201527f446f6573206e6f7420696d706c656d656e742074686520696e74657266616365604482015290519081900360640190fd5b600160a060020a03818116600081815260208181526040808320888452909152808220805473ffffffffffffffffffffffffffffffffffffffff19169487169485179055518692917f93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db15391a450505050565b600160a060020a03818116600090815260016020526040812054909116151561059a5750806105b7565b50600160a060020a03808216600090815260016020526040902054165b919050565b336105c683610570565b600160a060020a031614610624576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b81600160a060020a031681600160a060020a0316146106435780610646565b60005b600160a060020a03838116600081815260016020526040808220805473ffffffffffffffffffffffffffffffffffffffff19169585169590951790945592519184169290917f605c2dbf762e5f7d60a546d42e7205dcb1b011ebc62a61736a57c9089d3a43509190a35050565b600082826040516020018083838082843780830192505050925050506040516020818303038152906040528051906020012090505b92915050565b6106f882826107ef565b610703576000610705565b815b600160a060020a03928316600081815260208181526040808320600160e060020a031996909616808452958252808320805473ffffffffffffffffffffffffffffffffffffffff19169590971694909417909555908152600284528181209281529190925220805460ff19166001179055565b600080600160a060020a038416156107905783610792565b335b905061079d8361092a565b156107c357826107ad82826108aa565b6107b85760006107ba565b815b925050506106e8565b600160a060020a0390811660009081526020818152604080832086845290915290205416905092915050565b6000808061081d857f01ffc9a70000000000000000000000000000000000000000000000000000000061094c565b909250905081158061082d575080155b1561083d576000925050506106e8565b61084f85600160e060020a031961094c565b909250905081158061086057508015155b15610870576000925050506106e8565b61087a858561094c565b909250905060018214801561088f5750806001145b1561089f576001925050506106e8565b506000949350505050565b600160a060020a0382166000908152600260209081526040808320600160e060020a03198516845290915281205460ff1615156108f2576108eb83836107ef565b90506106e8565b50600160a060020a03808316600081815260208181526040808320600160e060020a0319871684529091529020549091161492915050565b7bffffffffffffffffffffffffffffffffffffffffffffffffffffffff161590565b6040517f01ffc9a7000000000000000000000000000000000000000000000000000000008082526004820183905260009182919060208160248189617530fa90519096909550935050505056fea165627a7a72305820377f4a2d4301ede9949f163f319021a6e9c687c292a5e2b2c4734c126b524e6c0029"
            )
        );

        mira = new MiraToken("MIRA", "MIRA", address(this));

        swap = new Swap();
        proxySwap = new TransparentUpgradeableProxy(address(swap), proxyOwner, "");
        swap = Swap(address(proxySwap));
        swap.initialize(address(mira), MIN_CSB, MIN_MIRA, admin);

        mira.mint(alice, INITIAL_MIRA_BALANCE);
        vm.deal(bob, INITIAL_CSB_BALANCE);
    }

    function testSetupStates() public {
        assertEq(address(swap.mira()), address(mira));
        assertEq(swap.getMinCsb(), MIN_CSB);
        assertEq(swap.getMinMira(), MIN_MIRA);
    }

    function testInitFail() public {
        // reinit
        vm.expectRevert(abi.encodePacked("Initializable: contract is already initialized"));
        swap.initialize(address(0x4), MIN_CSB, MIN_MIRA, admin);
    }

    function testPause() public {
        // expect events
        expectEmit(CheckAll);
        emit Paused(admin);
        vm.prank(admin);
        swap.pause();

        // check paused
        assertEq(swap.paused(), true);
    }

    function testPauseFail() public {
        // case 1: caller is not admin
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(this)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        swap.pause();
        // check paused
        assertEq(swap.paused(), false);

        // pause gateway
        vm.startPrank(admin);
        swap.pause();
        // case 2: gateway has been paused
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        swap.pause();
        vm.stopPrank();
    }

    function testUnpause() public {
        vm.prank(admin);
        swap.pause();
        // check paused
        assertEq(swap.paused(), true);

        // expect events
        expectEmit(CheckAll);
        emit Unpaused(admin);
        vm.prank(admin);
        swap.unpause();

        // check paused
        assertEq(swap.paused(), false);
    }

    function testUnpauseFail() public {
        // case 1: gateway not paused
        vm.expectRevert(abi.encodePacked("Pausable: not paused"));
        swap.unpause();
        // check paused
        assertEq(swap.paused(), false);

        // case 2: caller is not admin
        vm.prank(admin);
        swap.pause();
        // check paused
        assertEq(swap.paused(), true);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(this)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        swap.unpause();
        // check paused
        assertEq(swap.paused(), true);
    }

    function testSetMinMira() public {
        vm.prank(admin);
        swap.setMinMira(MIN_MIRA + 1);

        // check min MIRA
        assertEq(swap.getMinMira(), MIN_MIRA + 1);
    }

    function testSetMinMiraFailNotAdmin() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(this)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        swap.setMinMira(MIN_MIRA + 1);

        // check min MIRA
        assertEq(swap.getMinMira(), MIN_MIRA);
    }

    function testSetMinCsb() public {
        vm.prank(admin);
        swap.setMinCsb(MIN_CSB + 1);

        // check min CSB
        assertEq(swap.getMinCsb(), MIN_CSB + 1);
    }

    function testSetMinCsbFailNotAdmin() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(this)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        swap.setMinCsb(MIN_CSB + 1);

        // check min CSB
        assertEq(swap.getMinCsb(), MIN_CSB);
    }

    function testSellMIRA(uint256 miraAmount, uint256 expectedCsbAmount) public {
        vm.assume(miraAmount < INITIAL_CSB_BALANCE && miraAmount > MIN_MIRA);

        vm.startPrank(alice);
        mira.approve(address(swap), miraAmount);
        // expect event
        expectEmit(CheckAll);
        emit Approval(alice, address(swap), 0);
        expectEmit(CheckAll);
        emit Sent(address(swap), alice, address(swap), miraAmount, "", "");
        expectEmit(CheckAll);
        emit Transfer(alice, address(swap), miraAmount);
        expectEmit(CheckAll);
        emit Events.SellMIRA(alice, miraAmount, expectedCsbAmount, 1);
        swap.sellMIRA(miraAmount, expectedCsbAmount);
        vm.stopPrank();

        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE - miraAmount);
        assertEq(mira.balanceOf(address(swap)), miraAmount);
        // check sell order
        _checkSellOrder(1, address(alice), SELL_MIRA, miraAmount, expectedCsbAmount);
    }

    function testSellMIRAWithSend(uint256 miraAmount, uint256 expectedCsbAmount) public {
        vm.assume(miraAmount < INITIAL_CSB_BALANCE && miraAmount > MIN_MIRA);

        bytes memory data = abi.encode(OPERATION_TYPE_SELL_MIRA, expectedCsbAmount);

        // expect event
        expectEmit(CheckAll);
        emit Sent(alice, alice, address(swap), miraAmount, data, "");
        expectEmit(CheckAll);
        emit Transfer(alice, address(swap), miraAmount);
        expectEmit(CheckAll);
        emit Events.SellMIRA(alice, miraAmount, expectedCsbAmount, 1);
        vm.prank(alice);
        mira.send(address(swap), miraAmount, data);

        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE - miraAmount);
        assertEq(mira.balanceOf(address(swap)), miraAmount);
        // check sell order
        _checkSellOrder(1, address(alice), SELL_MIRA, miraAmount, expectedCsbAmount);
    }

    function testSellMIRAFailInvalidAmount(uint256 miraAmount) public {
        vm.assume(miraAmount < MIN_MIRA);

        vm.expectRevert(abi.encodePacked("InvalidMiraAmount"));
        // sell MIRA
        vm.prank(alice);
        swap.sellMIRA(miraAmount, 1);
    }

    function testSellMIRAFailInsufficientBalance(uint256 miraAmount) public {
        vm.assume(miraAmount > INITIAL_MIRA_BALANCE);

        // sell MIRA
        vm.startPrank(alice);
        mira.approve(address(swap), miraAmount);
        vm.expectRevert(abi.encodePacked("ERC777: transfer amount exceeds balance"));
        swap.sellMIRA(miraAmount, 1);
        vm.stopPrank();
    }

    function testCancelOrderWithSellMIRA(uint256 miraAmount) public {
        vm.assume(miraAmount < INITIAL_CSB_BALANCE && miraAmount > MIN_MIRA);

        // sell MIRA
        vm.startPrank(alice);
        mira.approve(address(swap), miraAmount);
        swap.sellMIRA(miraAmount, 1);

        // expect event
        expectEmit(CheckAll);
        emit Sent(address(swap), address(swap), alice, miraAmount, "", "");
        expectEmit(CheckAll);
        emit Transfer(address(swap), alice, miraAmount);
        expectEmit(CheckAll);
        emit Events.SellOrderCanceled(1);
        // cancel order
        swap.cancelOrder(1);
        vm.stopPrank();

        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE);
        assertEq(mira.balanceOf(address(swap)), 0);
        // check sell order
        _checkSellOrder(1, address(0), 0, 0, 0);
    }

    function testSellCSB(uint256 csbAmount, uint256 expectedMiraAmount) public {
        vm.assume(csbAmount < INITIAL_CSB_BALANCE && csbAmount > MIN_CSB);

        // expect event
        expectEmit(CheckAll);
        emit Events.SellCSB(bob, csbAmount, expectedMiraAmount, 1);
        vm.prank(bob);
        swap.sellCSB{value: csbAmount}(expectedMiraAmount);

        // check CSB balance
        assertEq(bob.balance, INITIAL_CSB_BALANCE - csbAmount);
        assertEq(address(swap).balance, csbAmount);
        // check sell order
        _checkSellOrder(1, address(bob), SELL_CSB, expectedMiraAmount, csbAmount);
    }

    function testSellCSBFailInvalidAmount(uint256 csbAmount) public {
        vm.assume(csbAmount < MIN_CSB);

        // sell CSB
        vm.expectRevert(abi.encodePacked("InvalidCSBAmount"));
        vm.prank(bob);
        swap.sellCSB{value: csbAmount}(1);
    }

    function testCancelOrderWithSellCSB(uint256 csbAmount) public {
        vm.assume(csbAmount < INITIAL_CSB_BALANCE && csbAmount > MIN_CSB);

        // sell CSB
        vm.startPrank(bob);
        swap.sellCSB{value: csbAmount}(1);

        // expect event
        expectEmit(CheckAll);
        emit Events.SellOrderCanceled(1);
        // cancel order
        swap.cancelOrder(1);
        vm.stopPrank();

        // check CSB balance
        assertEq(bob.balance, INITIAL_CSB_BALANCE);
        assertEq(address(swap).balance, 0);
        // check sell order
        _checkSellOrder(1, address(0), 0, 0, 0);
    }

    function testAcceptOrderSellCSB(uint256 csbAmount, uint256 expectedMiraAmount) public {
        vm.assume(csbAmount < INITIAL_CSB_BALANCE && csbAmount > MIN_CSB);
        vm.assume(expectedMiraAmount < INITIAL_MIRA_BALANCE);

        // bob sells CSB
        vm.prank(bob);
        swap.sellCSB{value: csbAmount}(expectedMiraAmount);

        // alice accepts bob's order
        vm.startPrank(alice);
        mira.approve(address(swap), expectedMiraAmount);
        // expect event
        expectEmit(CheckAll);
        emit Approval(alice, address(swap), 0);
        expectEmit(CheckAll);
        emit Sent(address(swap), alice, bob, expectedMiraAmount, "", "");
        expectEmit(CheckAll);
        emit Transfer(alice, bob, expectedMiraAmount);
        expectEmit(CheckAll);
        emit Events.SellOrderMatched(1, alice);
        swap.acceptOrder(1);

        // check CSB balance
        assertEq(alice.balance, csbAmount);
        assertEq(bob.balance, INITIAL_CSB_BALANCE - csbAmount);
        assertEq(address(swap).balance, 0);
        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE - expectedMiraAmount);
        assertEq(mira.balanceOf(address(bob)), expectedMiraAmount);
        assertEq(mira.balanceOf(address(swap)), 0);
        // check sell order
        _checkSellOrder(1, address(0), 0, 0, 0);
    }

    function testCancelOrderFailNotOwner() public {
        vm.expectRevert(abi.encodePacked("NotOrderOwner"));
        swap.cancelOrder(1);
    }

    function testAcceptOrderSellMIRA(uint256 miraAmount, uint256 expectedCsbAmount) public {
        vm.assume(miraAmount < INITIAL_CSB_BALANCE && miraAmount > MIN_MIRA);
        vm.assume(expectedCsbAmount < INITIAL_CSB_BALANCE);

        // alice sells MIRA
        vm.startPrank(alice);
        mira.approve(address(swap), miraAmount);
        swap.sellMIRA(miraAmount, expectedCsbAmount);
        vm.stopPrank();

        // bob accepts alice's sell order
        // expect event
        expectEmit(CheckAll);
        emit Sent(address(swap), address(swap), bob, miraAmount, "", "");
        expectEmit(CheckAll);
        emit Transfer(address(swap), bob, miraAmount);
        expectEmit(CheckAll);
        emit Events.SellOrderMatched(1, bob);
        vm.prank(bob);
        swap.acceptOrder{value: expectedCsbAmount}(1);

        // check CSB balance
        assertEq(alice.balance, expectedCsbAmount);
        assertEq(bob.balance, INITIAL_CSB_BALANCE - expectedCsbAmount);
        assertEq(address(swap).balance, 0);
        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE - miraAmount);
        assertEq(mira.balanceOf(address(bob)), miraAmount);
        assertEq(mira.balanceOf(address(swap)), 0);
        // check sell order
        _checkSellOrder(1, address(0), 0, 0, 0);
    }

    function testAcceptOrderSellCSBWithSend(uint256 csbAmount, uint256 expectedMiraAmount) public {
        vm.assume(csbAmount < INITIAL_CSB_BALANCE && csbAmount > MIN_CSB);
        vm.assume(expectedMiraAmount < INITIAL_MIRA_BALANCE && expectedMiraAmount > 0);

        // bob sells CSB
        vm.prank(bob);
        swap.sellCSB{value: csbAmount}(expectedMiraAmount);

        bytes memory data = abi.encode(OPERATION_TYPE_ACCEPT_ORDER, 1);

        // alice accepts bob's order
        // expect event
        expectEmit(CheckAll);
        emit Sent(alice, alice, address(swap), expectedMiraAmount, data, "");
        expectEmit(CheckAll);
        emit Transfer(alice, address(swap), expectedMiraAmount);
        expectEmit(CheckAll);
        emit Sent(address(swap), address(swap), bob, expectedMiraAmount, "", "");
        expectEmit(CheckAll);
        emit Transfer(address(swap), bob, expectedMiraAmount);
        expectEmit(CheckAll);
        emit Events.SellOrderMatched(1, alice);
        vm.prank(alice);
        mira.send(address(swap), expectedMiraAmount, data);

        // check CSB balance
        assertEq(alice.balance, csbAmount);
        assertEq(bob.balance, INITIAL_CSB_BALANCE - csbAmount);
        assertEq(address(swap).balance, 0);
        // check MIRA balance
        assertEq(mira.balanceOf(address(alice)), INITIAL_MIRA_BALANCE - expectedMiraAmount);
        assertEq(mira.balanceOf(address(bob)), expectedMiraAmount);
        assertEq(mira.balanceOf(address(swap)), 0);
        // check sell order
        _checkSellOrder(1, address(0), 0, 0, 0);
    }

    function testAcceptOrderFailInvalidCSBAmount(uint256 expectedCsbAmount) public {
        vm.assume(expectedCsbAmount > 1 && expectedCsbAmount < INITIAL_CSB_BALANCE);

        // alice sells MIRA
        vm.prank(alice);
        mira.send(address(swap), MIN_MIRA, abi.encode(OPERATION_TYPE_SELL_MIRA, expectedCsbAmount));

        vm.expectRevert(abi.encodePacked("InvalidCSBAmount"));
        vm.prank(bob);
        swap.acceptOrder{value: expectedCsbAmount - 1}(1);
    }

    function testAcceptOrderFailInvalidMiraAmount(uint256 expectedMiraAmount) public {
        vm.assume(expectedMiraAmount > 1 && expectedMiraAmount < INITIAL_MIRA_BALANCE);

        // bob sells CSB
        vm.prank(bob);
        swap.sellCSB{value: MIN_CSB}(expectedMiraAmount);

        vm.expectRevert(abi.encodePacked("InvalidMiraAmount"));
        vm.prank(alice);
        mira.send(
            address(swap),
            expectedMiraAmount - 1,
            abi.encode(OPERATION_TYPE_ACCEPT_ORDER, uint256(1))
        );
    }

    function testAcceptOrderFailInvalidOrder() public {
        vm.expectRevert(abi.encodePacked("InvalidOrder"));
        vm.prank(alice);
        mira.send(address(swap), 1, abi.encode(OPERATION_TYPE_ACCEPT_ORDER, uint256(1)));
    }

    function testTokensReceivedFailInvalidAmount() public {
        vm.expectRevert(abi.encodePacked("InvalidAmount"));
        vm.prank(alice);
        mira.send(address(swap), 0, "");
    }

    function testTokensReceivedFailInvalidData() public {
        vm.expectRevert(abi.encodePacked("InvalidData"));
        vm.prank(alice);
        mira.send(address(swap), 1, abi.encode(uint256(10), uint256(3)));
    }

    function testCantDoAnythingWhenPaused() public {
        vm.prank(admin);
        swap.pause();

        vm.startPrank(bob);
        // sell CSB
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        swap.sellCSB{value: MIN_CSB}(MIN_MIRA);

        // accept order
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        swap.acceptOrder(1);

        // cancel order
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        swap.cancelOrder(1);
        vm.stopPrank();

        vm.startPrank(alice);
        // sell MIRA
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        swap.sellMIRA(MIN_MIRA, MIN_CSB);

        // accept order with sending MIRA
        vm.expectRevert(abi.encodePacked("Pausable: paused"));
        mira.send(address(swap), MIN_MIRA, abi.encode(OPERATION_TYPE_ACCEPT_ORDER, uint256(1)));
        vm.stopPrank();
    }

    function _checkSellOrder(
        uint256 orderId,
        address owner,
        uint8 orderType,
        uint256 miraAmount,
        uint256 csbAmount
    ) internal {
        DataTypes.SellOrder memory order = swap.getOrder(orderId);
        assertEq(order.owner, owner);
        assertEq(order.orderType, orderType);
        assertEq(order.miraAmount, miraAmount);
        assertEq(order.csbAmount, csbAmount);
    }
}
