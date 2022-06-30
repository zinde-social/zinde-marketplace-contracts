// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/MarketPlace.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Events.sol";
import "../src/mocks/MockWeb3Entry.sol";
import "../src/mocks/WCSB.sol";
import "../src/mocks/NFT.sol";

contract MarketPlaceTest is Test {
    MarketPlace market;
    MockWeb3Entry web3Entry;
    WCSB wcsb;
    NFT nft;

    address alice = address(0x1234);

    function setUp() public {
        market = new MarketPlace();
        wcsb = new WCSB();
        nft = new NFT();
        web3Entry = new MockWeb3Entry(address(nft));

        market.initialize(address(web3Entry), address(wcsb));

        nft.mint(alice);
        web3Entry.mintCharacter(alice);
    }

    function testExpectRevertReinitial() public {
        assertEq(market.web3Entry(), address(web3Entry));
        assertEq(market.WCSB(), address(wcsb));

        // reinit
        vm.expectRevert(
            abi.encodePacked("Initializable: contract is already initialized")
        );
        market.initialize(address(0x3), address(0x4));
    }

    function testExpectRevertSetRoyalty() public {
        vm.expectRevert(abi.encodePacked("InvalidPercentage"));
        market.setRoyalty(address(0x1), 1, 1, address(0x2), 101);

        vm.expectRevert(abi.encodePacked("NotCharacterOwner"));
        market.setRoyalty(address(0x1), 1, 1, address(0x2), 100);

        vm.prank(alice);
        vm.expectRevert(abi.encodePacked("InvalidToken"));
        market.setRoyalty(address(0x1), 1, 1, address(0x2), 100);
    }

    function testSetGetRoyalty() public {
        DataTypes.Royalty memory royalty = market.getRoyalty(address(nft));
        assertEq(royalty.receiver, address(0x0));
        assertEq(royalty.percentage, 0);

        // set royalty
        vm.prank(alice);
        market.setRoyalty(address(nft), 1, 1, alice, 100);

        // get royalty
        royalty = market.getRoyalty(address(nft));
        assertEq(royalty.receiver, alice);
        assertEq(royalty.percentage, 100);
    }

    function testExpectEmitRoyaltySet() public {
        vm.expectEmit(true, true, false, true);
        // The event we expect
        emit Events.RoyaltySet(alice, address(nft), alice, 100);
        // The event we get
        vm.prank(alice);
        market.setRoyalty(address(nft), 1, 1, alice, 100);
    }
}