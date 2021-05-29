// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IERC721 {
    function mint(
        address recipient,
        uint256 tokenId,
        string memory uri
    ) external;
}

contract AFENNFTAuction {
    using SafeMath for uint256; //add safeMath

    // keep track of counters
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address public dev; // developer address
    address public team; // address of the team

    uint256 distribution; // distribution percentage between the DAO and the team

    IERC721 public immutable NFT;

    struct Auction {
        uint256 originalQuantity; // quantity of the NFT's to give
        string uri; // URI of the NFT
        IERC20 auctionToken;
        // uint256 basePrice; // base price of the asset
        uint256 minBidAmt; // minimum amount at which auction should increase
        uint256 incrementRate; // rate at which the big should increment
        uint256 startTime; // time at which the auction will start
        uint256 expiry; // expiry of the auction
        uint256 totalBidders; // total number of bids
        uint256 totalBidAmt; // total bid amount
        uint256 burnRate; // by default zero, can be enabled later
        mapping(address => uint256) bids; // mapping of all the bids with amount they staked
        mapping(address => uint256) bidderPosition;
        mapping(address => bool) hasClaimed;
    }

    // store the mapping of added NFTs for the sale
    mapping(uint256 => Auction) public auctions;

    event Bid(
        uint256 indexed auctionId,
        address indexed user,
        uint256 indexed amount
    );

    event Claim(
        uint256 indexed auctionId,
        address indexed user,
        uint256 indexed tokenId
    );

    event NewAuction(uint256 indexed auctionId);

    event IncrementRate(uint256 indexed asset, uint256 indexed incrementRate);

    event ChangeSalesDistribution(uint256 indexed newDistributionRate);

    event ChangeBurnRate(uint256 indexed newBurnRate);

    modifier onlyDev() {
        require(msg.sender == dev, "auction: wrong developer");
        _;
    }

    constructor(
        IERC721 _NFTAddress,
        address _dev,
        address _team
    ) {
        NFT = _NFTAddress;
        dev = _dev;
        team = _team;
    }

    /**
     * @dev A user can bid, he provide amount in ratio with minBidAmt
     * @param _auctionId id of the auction
     * @param _amt Amount users want to bid
     */
    function bid(uint256 _auctionId, uint256 _amt) public {
        Auction storage auction = auctions[_auctionId];

        require(auction.startTime < block.timestamp, "auction: not yet started");
        require(_amt > 0, "auction: amount should be greater than zero");
        require(
            auction.expiry > block.timestamp,
            "Auction: Auction is not over yet"
        );
        require(
            auction.minBidAmt < _amt && // _amt should be > than last bidded price
                _amt.sub(auction.minBidAmt).mod(auction.incrementRate) == 0, // proposed bid is multiple of minimum bid amount
            "auction: invalid amount"
        );
        require(auction.minBidAmt < _amt, "big amount is too less");

        // return the previous amount
        if (auction.bids[msg.sender] > 0) {
            auction.auctionToken.transfer(msg.sender, auction.bids[msg.sender]);

        }

        // update the amount user has staked
        uint256 newBidderAmt = _amt;
        auction.bids[msg.sender] = newBidderAmt;

        // auction.highestBidAmt = _amt.add(newBidderAmt);
        // // update the highest bid amount
        // if (auction.highestBidAmt < _amt.add(newBidderAmt)) {
        //     auction.highestBidAmt = _amt.add(newBidderAmt);
        // }

        // update last bid amount
        auction.minBidAmt = _amt;

        // update the totalBidAmt
        auction.totalBidAmt = auction.totalBidAmt.add(_amt);

        // update number of bidders
        auction.totalBidders = auction.totalBidders.add(1);

        // store index to distribute the reward
        auction.bidderPosition[msg.sender] = auction.totalBidders;

        // transfer the tokens to contract
        auction.auctionToken.transferFrom(msg.sender, address(this), _amt);

        // emit bid event
        emit Bid(_auctionId, msg.sender, _amt);
    }

    /**
     * After the auction has ended users can claim their NFTs or the auction tokens (in case they do not win)
     * @param _auctionId id of the auction
     */
    function claim(uint256 _auctionId) public {
        Auction storage auction = auctions[_auctionId];

        require(
            auction.hasClaimed[msg.sender] == false,
            "auction: Already claimed"
        );
        require(auction.bids[msg.sender] > 0, "auction: invalid user");

        require(
            auction.expiry < block.timestamp,
            "Auction: Auction is not over yet"
        );

        if (auction.totalBidders.sub(auction.bidderPosition[msg.sender]) == 0) {
            _tokenIds.increment();
            uint256 tokenId = _tokenIds.current();
            NFT.mint(msg.sender, tokenId, auction.uri);
            emit Claim(_auctionId, msg.sender, tokenId);
        } else if (
            auction.totalBidders.sub(auction.bidderPosition[msg.sender]) <=
            auction.originalQuantity
        ) {
            _tokenIds.increment();
            uint256 tokenId = _tokenIds.current();
            NFT.mint(msg.sender, tokenId, auction.uri);
            auction.hasClaimed[msg.sender] = true;
            emit Claim(
                _auctionId,
                msg.sender,
                auction.totalBidders.sub(auction.bidderPosition[msg.sender])
            );
        } else {
            auction.auctionToken.transfer(msg.sender, auction.bids[msg.sender]);
        }
    }

    /**
     * Returns the bid amount provided by user
     * @param _auctionId id of the auction
     * @param _user address of the user
     */
    function getBid(uint256 _auctionId, address _user)
        public
        view
        returns (uint256)
    {
        Auction storage auction = auctions[_auctionId];
        return auction.bids[_user];
    }

    /**
     * Returns position of the bidder
     * @param _auctionId id of the auction
     * @param _user address of the user
     */
    function getBidderPosition(uint256 _auctionId, address _user)
        public
        view
        returns (uint256)
    {
        Auction storage auction = auctions[_auctionId];
        return auction.bidderPosition[_user];
    }

    /*
    DEV FUNCTIONS
    */
    /**
     * Add new NFT for sale
     * @param _auctionId The address of the asset should be sold
     * @param _uri uri of the NFT
     * @param _quantity The quantity of the asset should be sold
     * @param _minBidAmt Minimum bid amount to be provided to participate in auction
     * @param _incrementRate The rate at which the bids should be incremented
     * @param _expiry Expiry of the NFT sale
     * @param _auctionToken The token in which the auction should commence
     */

    function add(
        uint256 _auctionId,
        string memory _uri,
        uint256 _quantity,
        uint256 _minBidAmt,
        uint256 _incrementRate,
        uint256 _expiry,
        uint256 _startTime,
        IERC20 _auctionToken
    ) external onlyDev {
        require(
            _quantity > 0,
            "auction: _quantity should be greater than zero"
        );
        require(
            _expiry > block.timestamp,
            "auction: _expiry should be a future block"
        );
        require(
            _minBidAmt > 0,
            "auction: _minBidAmt should be greater than zero"
        );
        Auction storage auction = auctions[_auctionId];
        // check if the asset is already added
        require(auction.minBidAmt == 0);
        auction.uri = _uri;
        auction.originalQuantity = _quantity;
        // auction.basePrice = _basePrice;
        auction.minBidAmt = _minBidAmt;
        auction.incrementRate = _incrementRate;
        auction.expiry = _expiry;
        auction.auctionToken = _auctionToken;
        auction.startTime = _startTime;
        emit NewAuction(_auctionId);
    }

    function changeIncrementRate(uint256 _auctionId, uint256 _incrementRate)
        external
        onlyDev
    {
        require(_incrementRate > 0, "auction: invalid inputs");
        Auction storage auction = auctions[_auctionId];
        auction.incrementRate = _incrementRate;
        emit IncrementRate(_auctionId, _incrementRate);
    }

    // set distribution percentage to DAO, in decimal of 4
    // eg. for 50% set value to be 50000
    function changeSalesDistribution(uint256 _newDistribution)
        external
        onlyDev
    {
        distribution = _newDistribution;
        emit ChangeSalesDistribution(_newDistribution);
    }

    // for 50% set value to be 50000
    function changeBurnRate(uint256 _auctionId, uint256 _newBurnRate)
        external
        onlyDev
    {
        Auction storage auction = auctions[_auctionId];
        auction.burnRate = _newBurnRate;
        emit ChangeBurnRate(_newBurnRate);
    }

    function distributeSales(uint256 _auctionId) external onlyDev {
        Auction storage auction = auctions[_auctionId];
        require(
            auction.expiry <= block.timestamp,
            "auction: the auction isn't expired"
        );

        uint256 saleAmount;

        // burn tokens
        if (auction.burnRate > 0) {
            uint256 burnAmount =
                auction.minBidAmt.mul(auction.burnRate).div(1000000);
            auction.auctionToken.transfer(address(0), burnAmount);
            saleAmount = auction.minBidAmt.sub(burnAmount);
        } else {
            saleAmount = auction.minBidAmt;
        }

        // distribute funds to developer w.r.t to already set distribution
        uint256 devShare = saleAmount.mul(distribution).div(1000000);
        auction.auctionToken.transfer(dev, devShare);
        // distribute remaining balance to the team
        auction.auctionToken.transfer(team, saleAmount.sub(devShare));
    }
}
