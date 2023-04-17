// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IMarketPlace} from "./interfaces/IMarketPlace.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {Constants} from "./libraries/Constants.sol";
import {Events} from "./libraries/Events.sol";
import {MarketPlaceStorage} from "./storage/MarketPlaceStorage.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MarketPlace is IMarketPlace, Context, ReentrancyGuard, Initializable, MarketPlaceStorage {
    using SafeERC20 for IERC20;

    bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    modifier askNotExists(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory askOrder = _askOrders[nftAddress][tokenId][user];
        require(askOrder.deadline == 0, "AskExists");
        _;
    }

    modifier askExists(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory askOrder = _askOrders[nftAddress][tokenId][user];
        require(askOrder.deadline > 0, "AskNotExists");
        _;
    }

    modifier validAsk(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory askOrder = _askOrders[nftAddress][tokenId][user];
        require(askOrder.deadline >= _now(), "AskExpiredOrNotExists");
        _;
    }

    modifier bidNotExists(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory bidOrder = _bidOrders[nftAddress][tokenId][user];
        require(bidOrder.deadline == 0, "BidExists");
        _;
    }

    modifier bidExists(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory bidOrder = _bidOrders[nftAddress][tokenId][user];
        require(bidOrder.deadline > 0, "BidNotExists");
        _;
    }

    modifier validBid(
        address nftAddress,
        uint256 tokenId,
        address user
    ) {
        DataTypes.Order memory bidOrder = _bidOrders[nftAddress][tokenId][user];
        require(bidOrder.deadline != 0, "BidNotExists");
        require(bidOrder.deadline >= _now(), "BidExpired");
        _;
    }

    modifier validPayToken(address payToken) {
        require(payToken == WCSB || payToken == Constants.NATIVE_CSB, "InvalidPayToken");
        _;
    }

    modifier validDeadline(uint256 deadline) {
        require(deadline > _now(), "InvalidDeadline");
        _;
    }

    modifier validPrice(uint256 price) {
        require(price > 0, "InvalidPrice");
        _;
    }

    /// @inheritdoc IMarketPlace
    function initialize(address wcsb_) external override initializer {
        WCSB = wcsb_;
    }

    /// @inheritdoc IMarketPlace

    /// @inheritdoc IMarketPlace
    function ask(
        address nftAddress,
        uint256 tokenId,
        address payToken,
        uint256 price,
        uint256 deadline
    )
        external
        override
        askNotExists(nftAddress, tokenId, _msgSender())
        validPayToken(payToken)
        validDeadline(deadline)
        validPrice(price)
    {
        require(IERC165(nftAddress).supportsInterface(INTERFACE_ID_ERC721), "TokenNotERC721");
        require(IERC721(nftAddress).ownerOf(tokenId) == _msgSender(), "NotERC721TokenOwner");

        // save sell order
        _askOrders[nftAddress][tokenId][_msgSender()] = DataTypes.Order(
            _msgSender(),
            nftAddress,
            tokenId,
            payToken,
            price,
            deadline
        );

        emit Events.AskCreated(_msgSender(), nftAddress, tokenId, WCSB, price, deadline);
    }

    /// @inheritdoc IMarketPlace
    function updateAsk(
        address nftAddress,
        uint256 tokenId,
        address payToken,
        uint256 price,
        uint256 deadline
    )
        external
        override
        askExists(nftAddress, tokenId, _msgSender())
        validPayToken(payToken)
        validDeadline(deadline)
        validPrice(price)
    {
        DataTypes.Order storage askOrder = _askOrders[nftAddress][tokenId][_msgSender()];
        // update ask order
        askOrder.payToken = payToken;
        askOrder.price = price;
        askOrder.deadline = deadline;

        emit Events.AskUpdated(_msgSender(), nftAddress, tokenId, payToken, price, deadline);
    }

    /// @inheritdoc IMarketPlace
    function cancelAsk(
        address nftAddress,
        uint256 tokenId
    ) external override askExists(nftAddress, tokenId, _msgSender()) {
        delete _askOrders[nftAddress][tokenId][_msgSender()];

        emit Events.AskCanceled(_msgSender(), nftAddress, tokenId);
    }

    /// @inheritdoc IMarketPlace
    function acceptAsk(
        address nftAddress,
        uint256 tokenId,
        address user
    ) external payable override nonReentrant validAsk(nftAddress, tokenId, user) {
        DataTypes.Order memory askOrder = _askOrders[nftAddress][tokenId][user];

        (address royaltyReceiver, uint256 royaltyAmount) = _royaltyInfo(
            nftAddress,
            tokenId,
            askOrder.price
        );
        // pay to owner
        _payWithRoyalty(
            _msgSender(),
            askOrder.owner,
            askOrder.payToken,
            askOrder.price,
            royaltyReceiver,
            royaltyAmount
        );
        // transfer nft
        IERC721(nftAddress).safeTransferFrom(user, _msgSender(), tokenId);

        emit Events.OrdersMatched(
            askOrder.owner,
            _msgSender(),
            nftAddress,
            tokenId,
            askOrder.payToken,
            askOrder.price,
            royaltyReceiver,
            royaltyAmount
        );

        delete _askOrders[nftAddress][tokenId][user];
    }

    /// @inheritdoc IMarketPlace
    function bid(
        address nftAddress,
        uint256 tokenId,
        address payToken,
        uint256 price,
        uint256 deadline
    )
        external
        override
        bidNotExists(nftAddress, tokenId, _msgSender())
        validPayToken(payToken)
        validDeadline(deadline)
        validPrice(price)
    {
        require(payToken != Constants.NATIVE_CSB, "NativeCSBNotAllowed");
        require(IERC165(nftAddress).supportsInterface(INTERFACE_ID_ERC721), "TokenNotERC721");

        // save buy order
        _bidOrders[nftAddress][tokenId][_msgSender()] = DataTypes.Order(
            _msgSender(),
            nftAddress,
            tokenId,
            payToken,
            price,
            deadline
        );

        emit Events.BidCreated(_msgSender(), nftAddress, tokenId, payToken, price, deadline);
    }

    /// @inheritdoc IMarketPlace
    function cancelBid(
        address nftAddress,
        uint256 tokenId
    ) external override bidExists(nftAddress, tokenId, _msgSender()) {
        delete _bidOrders[nftAddress][tokenId][_msgSender()];

        emit Events.BidCanceled(_msgSender(), nftAddress, tokenId);
    }

    /// @inheritdoc IMarketPlace
    function updateBid(
        address nftAddress,
        uint256 tokenId,
        address payToken,
        uint256 price,
        uint256 deadline
    )
        external
        override
        validBid(nftAddress, tokenId, _msgSender())
        validPayToken(payToken)
        validDeadline(deadline)
        validPrice(price)
    {
        DataTypes.Order storage bidOrder = _bidOrders[nftAddress][tokenId][_msgSender()];
        // update buy order
        bidOrder.payToken = payToken;
        bidOrder.price = price;
        bidOrder.deadline = deadline;

        emit Events.BidUpdated(_msgSender(), nftAddress, tokenId, payToken, price, deadline);
    }

    /// @inheritdoc IMarketPlace
    function acceptBid(
        address nftAddress,
        uint256 tokenId,
        address user
    ) external override nonReentrant validBid(nftAddress, tokenId, user) {
        DataTypes.Order memory bidOrder = _bidOrders[nftAddress][tokenId][user];

        (address royaltyReceiver, uint256 royaltyAmount) = _royaltyInfo(
            nftAddress,
            tokenId,
            bidOrder.price
        );
        // pay to msg.sender
        _payWithRoyalty(
            bidOrder.owner,
            _msgSender(),
            bidOrder.payToken,
            bidOrder.price,
            royaltyReceiver,
            royaltyAmount
        );
        // transfer nft
        IERC721(nftAddress).safeTransferFrom(_msgSender(), user, tokenId);

        emit Events.OrdersMatched(
            _msgSender(),
            bidOrder.owner,
            nftAddress,
            tokenId,
            bidOrder.payToken,
            bidOrder.price,
            royaltyReceiver,
            royaltyAmount
        );

        delete _bidOrders[nftAddress][tokenId][user];
    }

    /// @inheritdoc IMarketPlace
    function getAskOrder(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) external view override returns (DataTypes.Order memory) {
        return _askOrders[nftAddress][tokenId][owner];
    }

    /// @inheritdoc IMarketPlace
    function getBidOrder(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) external view override returns (DataTypes.Order memory) {
        return _bidOrders[nftAddress][tokenId][owner];
    }

    function _payWithRoyalty(
        address from,
        address to,
        address token,
        uint256 amount,
        address royaltyReceiver,
        uint256 royaltyAmount
    ) internal {
        if (token == Constants.NATIVE_CSB) {
            require(msg.value >= amount, "NotEnoughFunds");

            // pay CSB
            if (royaltyReceiver != address(0)) {
                payable(royaltyReceiver).transfer(royaltyAmount);
                // slither-disable-next-line arbitrary-send-eth
                payable(to).transfer(amount - royaltyAmount);
            } else {
                // slither-disable-next-line arbitrary-send-eth
                payable(to).transfer(amount);
            }
        } else {
            // refund CSB
            if (msg.value > 0) {
                payable(from).transfer(msg.value);
            }
            // pay ERC20
            if (royaltyReceiver != address(0)) {
                IERC20(token).safeTransferFrom(from, royaltyReceiver, royaltyAmount);
                IERC20(token).safeTransferFrom(from, to, amount - royaltyAmount);
            } else {
                IERC20(token).safeTransferFrom(from, to, amount);
            }
        }
    }

    function _royaltyInfo(
        address nftAddress,
        uint256 tokenId,
        uint256 salePrice
    ) internal view returns (address royaltyReceiver, uint256 royaltyAmount) {
        if (IERC165(nftAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyReceiver, royaltyAmount) = IERC2981(nftAddress).royaltyInfo(tokenId, salePrice);
        }
    }

    function _now() internal view virtual returns (uint256) {
        // slither-disable-next-line timestamp
        return block.timestamp;
    }
}