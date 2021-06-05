const { 
	deployContract, 
	deployMockContract, 
	MockContract 
} = require('ethereum-waffle');
const { BigNumber } = require('ethers');
const { ethers } = require('hardhat');
// const {
// 	BN,
// 	constants,
// 	expectEvent,
// 	expectRevert
// } = require('@openzeppelin/test-helpers');

const { getProvider } = require('./helpers/contract');
const AFENNFTAuctionArtifact = require('../artifacts/contracts/auction/AFENNFTAuction.sol/AFENNFTAuction.json');
const ERC721MockArtifact = require('../artifacts/contracts/mocks/ERC721Mock.sol/ERC721Mock.json');
const ERC20MockArtifact = require('../artifacts/contracts/mocks/AFEN.sol/AFEN.json');
const { expect } = require('chai');

const [alice, bob, carl] = getProvider().getWallets();

describe('AFENNFTAuction', async () => {
	let afen, nft;
	let auction;

	const nftName = 'cryptokitties';
	const nftSymbol = 'CK';
	const decimalsPowed = BigNumber.from(10).pow(18);

	beforeEach(async () => {

		await deployContract(
			alice,
			ERC20MockArtifact,
			[]
		).then((instance) => {
			afen = instance;
		});

		await deployContract(
			alice, 
			ERC721MockArtifact, 
			[
				nftName,
				nftSymbol
			]
		).then((instance) => {
			nft = instance;
		});
		await deployContract(
			alice,
			AFENNFTAuctionArtifact,
			[
				nft.address,
				alice.address
			]
		).then((instance) => {
			auction = instance;
		});

		bobauction = await  auction.connect(bob);

		await afen.transfer(bob.address, BigNumber.from(1000).mul(decimalsPowed));
	});

	describe('Add', async () => {
		describe('Revert if', async () => {
			it('Quantity is 0', async () => {
				await expect(auction.add(
					BigNumber.from(1),
					'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
					BigNumber.from(0),
					BigNumber.from(1000),
					BigNumber.from(120),
					BigNumber.from(Math.ceil((new Date()).getTime() / 1000) + 1000),
					BigNumber.from(Math.round((new Date()).getTime() / 1000)),
					afen.address
				)).to.be.revertedWith('Auction: _quantity should be greater than zero');
			});

			it('Auction has expired', async () => {
				await expect(auction.add(
					BigNumber.from(1),
					'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
					BigNumber.from(1),
					BigNumber.from(1000),
					BigNumber.from(120),
					BigNumber.from(Math.round((new Date()).getTime() / 1000) - 100),
					BigNumber.from(Math.round((new Date()).getTime() / 1000)),
					afen.address
				)).to.be.revertedWith('Auction: _expiry should be a future block');
			});

			it('Mininum Bid amount is 0', async () => {
				await expect(auction.add(
					BigNumber.from(1),
					'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
					BigNumber.from(1),
					BigNumber.from(0),
					BigNumber.from(120),
					BigNumber.from(Math.ceil((new Date()).getTime() / 1000) + 1000),
					BigNumber.from(Math.round((new Date()).getTime() / 1000)),
					afen.address
				)).to.be.revertedWith('Auction: _minBidAmt should be greater than zero');
			});
		});
	});

	describe('bid', async () => {

		it('Transfer the tokens to contract checking', async () => {
			await auction.add(
				BigNumber.from(1),
				'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
				BigNumber.from(1),
				BigNumber.from(20),
				BigNumber.from(10),
				BigNumber.from(Math.round((new Date()).getTime() / 1000) + 5000),
				BigNumber.from(Math.round((new Date()).getTime() / 1000) - 1000),
				afen.address
			);

			await afen.approve(auction.address, BigNumber.from(100).mul(decimalsPowed)); // 100 AFEN

			await auction.bid(
				BigNumber.from(1),
				BigNumber.from(100).mul(decimalsPowed)
			);
			await afen.balanceOf(alice.address).then(balance => {
				expect(balance.toString()).to.equal('999998900000000000000000000');
			});
		});

		describe('Revert if', async () => {
			it('Auction start time checking', async () => {
				await auction.add(
					BigNumber.from(1),
					'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
					BigNumber.from(1),
					BigNumber.from(1),
					BigNumber.from(120),
					BigNumber.from(Math.round((new Date()).getTime() / 1000) + 5000),
					BigNumber.from(Math.round((new Date()).getTime() / 1000) + 1000),
					afen.address
				);
	
				await expect(auction.bid(
					BigNumber.from(1),
					BigNumber.from(1000)
				)).to.be.revertedWith('Auction: Auction is not started yet');
	
			});

			it('Bid amount is 0', async () => {
				await expect(auction.bid(
					BigNumber.from(1),
					BigNumber.from(0)
				)).to.be.revertedWith('Auction: Amount should be greater than zero');
			});

			it('Auction bid amount checking with mininum bid amount', async () => {
				await auction.add(
					BigNumber.from(1),
					'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
					BigNumber.from(1),
					BigNumber.from(100),
					BigNumber.from(1),
					BigNumber.from(Math.round((new Date()).getTime() / 1000) + 5000),
					BigNumber.from(Math.round((new Date()).getTime() / 1000) - 1000),
					afen.address
				);
	
				await expect(auction.bid(
					BigNumber.from(1),
					BigNumber.from(50)
				)).to.be.revertedWith('Auction: Bid amount is too less');
	
			});

		}); 
	});


	describe('Claim', async () => {
		it('Mint checking', async () => {

			await auction.add(
				BigNumber.from(1),
				'ipfs/bafybeifszd4wbkeekwzwitvgijrw6zkzijxutm4kdumkxnc6677drtslni/ipfs-logo-768px.png',
				BigNumber.from(1),
				BigNumber.from(50),
				BigNumber.from(10),
				BigNumber.from(Math.round((new Date()).getTime() / 1000) + 5000),
				BigNumber.from(Math.round((new Date()).getTime() / 1000) - 1000),
				afen.address
			);

			await afen.approve(auction.address, BigNumber.from(100).mul(decimalsPowed)); // 100 AFEN

			await auction.bid(
				BigNumber.from(1),
				BigNumber.from(100).mul(decimalsPowed)
			);

			await auction.endAuction(1);

			await auction.claim(
				BigNumber.from(1)
			);
			// await expect(nft.ownerOf(1)).to.equal(alice.address);

			nft.ownerOf(1);
		});
		
	});

});
