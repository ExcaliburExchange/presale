const {BN, constants, expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const time = require('./utils/timeContractSimulator');
const {it} = require("truffle/build/131.bundled");

const Presale = artifacts.require('PresaleMock');
const EXCToken = artifacts.require('excalibur/EXCToken');
const GRAILToken = artifacts.require('excalibur/GRAILToken');
const WFTMToken = artifacts.require('WETH9');
const Dividends = artifacts.require('excalibur/Dividends');

contract('Presale', function (accounts) {
  const [deployer, alice, bob, carol, dave] = accounts;

  const randomFactoryAddress = "0x55bF929d9278e8B40043479e2C088e1bcF5B9F1B";
  let startTime = new BN(100);
  let endTime = new BN(500);

  beforeEach(async function () {
    this.excToken = await EXCToken.new(deployer, new BN(1000000), { from: deployer });
    this.wftmToken = await WFTMToken.new(deployer, new BN(100000), { from: deployer });
    this.grailToken = await GRAILToken.new(0, 0, 0, this.excToken.address, { from: deployer });
    this.dividends = await Dividends.new(this.grailToken.address, new BN(0), {from: deployer});

    this.presale = await Presale.new(
      this.excToken.address, this.wftmToken.address, randomFactoryAddress, this.dividends.address,
      startTime, endTime, { from: deployer }
    );
  })

  // it('has correct EXC address', async function() {
  //   expect(await this.presale.EXC()).to.be.equal(this.excToken.address);
  // })
  //
  // it('has correct WFTM address', async function() {
  //   expect(await this.presale.WFTM()).to.be.equal(this.wftmToken.address);
  // })
  //
  // it('has correct factory address', async function() {
  //   expect(await this.presale.FACTORY()).to.be.equal(randomFactoryAddress);
  // })
  //
  // it('has correct dividends address', async function() {
  //   expect(await this.presale.DIVIDENDS()).to.be.equal(this.dividends.address);
  // })
  //
  // it('has correct startTime', async function() {
  //   expect(await this.presale.START_TIME()).to.be.bignumber.equal(startTime);
  // })
  //
  // it('has correct endTime', async function() {
  //   expect(await this.presale.END_TIME()).to.be.bignumber.equal(endTime);
  // })
  //
  // describe('owner', function () {
  //   describe('when contract is initialized', function() {
  //     it('has deployer as owner', async function() {
  //       expect(await this.presale.owner()).to.be.equal(deployer);
  //     });
  //   });
  //
  //   describe('when owner has changed', function() {
  //     beforeEach(async function() {
  //       await this.presale.transferOwnership(bob);
  //     });
  //
  //     it('has new owner as owner', async function() {
  //       expect(await this.presale.owner()).to.be.equal(bob);
  //     });
  //   });
  // })
  //
  // describe('getRemainingTime', function() {
  //   describe('when presale has not started', function() {
  //     beforeEach(async function() {
  //      await time.increaseTo(this.presale, startTime.subn(1));
  //     })
  //     it('hasStarted', async function() {
  //       expect(await this.presale.hasStarted()).to.equal(false);
  //     })
  //     it('hasEnded', async function() {
  //       expect(await this.presale.hasEnded()).to.equal(false);
  //     })
  //     it('getRemainingTime', async function() {
  //       expect(await this.presale.getRemainingTime()).to.be.bignumber.equal(endTime.sub(startTime.subn(1)));
  //     })
  //   })
  //
  //   describe('when presale has started', function() {
  //     beforeEach(async function() {
  //       await time.increaseTo(this.presale, startTime)
  //     })
  //     it('hasStarted', async function() {
  //       expect(await this.presale.hasStarted()).to.equal(true)
  //     })
  //     it('hasEnded', async function() {
  //       expect(await this.presale.hasEnded()).to.equal(false)
  //     })
  //     it('getRemainingTime', async function() {
  //       expect(await this.presale.getRemainingTime()).to.be.bignumber.equal(endTime.sub(startTime))
  //     })
  //   })
  //
  //   describe('when presale has ended', function() {
  //     beforeEach(async function() {
  //       await time.increaseTo(this.presale, endTime)
  //     })
  //     it('hasStarted', async function() {
  //       expect(await this.presale.hasStarted()).to.equal(true)
  //     })
  //     it('hasEnded', async function() {
  //       expect(await this.presale.hasEnded()).to.equal(true)
  //     })
  //     it('getRemainingTime', async function() {
  //       expect(await this.presale.getRemainingTime()).to.be.bignumber.equal(new BN(0))
  //     })
  //   })
  // })

  describe('buy', function () {
    describe('when presale has not started', function() {
      beforeEach(async function () {
        await time.increaseTo(this.presale, startTime.subn(1));
      })
      it('reverts', async function() {
        await expectRevert(this.presale.buy(alice, {from: alice, value: new BN(10)}), "isActive: sale is not active");
      })
    })

    describe('when presale is active', function() {
      beforeEach(async function() {
        await time.increaseTo(this.presale, startTime)
      })

      describe('when amount is 0', function() {
        it('reverts', async function() {
          await expectRevert(this.presale.buy(alice, {from: alice, value: new BN(0)}), "buy: zero amount");
        })
      })

      describe('when purchases are made', function() {
        let aliceInfo
        let bobInfo
        let carolInfo

        beforeEach(async function() {
          await this.presale.buy(constants.ZERO_ADDRESS, {from: alice, value: new BN(100)})
          await this.presale.buy(alice, {from: bob, value: new BN(900)})
          await this.presale.buy(alice, {from: carol, value: new BN(2300)})
          aliceInfo = await this.presale.getUserInfo(alice);
          bobInfo = await this.presale.getUserInfo(bob);
          carolInfo = await this.presale.getUserInfo(carol);
        })

        it('has correct allocations', async function() {
          expect(aliceInfo.allocation).to.be.bignumber.equal(new BN(100));
          expect(bobInfo.allocation).to.be.bignumber.equal(new BN(900));
          expect(carolInfo.allocation).to.be.bignumber.equal(new BN(2300));
        })
      })


    })

    describe('when presale has ended', function() {
      beforeEach(async function() {
        await time.increaseTo(this.presale, endTime)
      })
      it('reverts', async function() {
        await expectRevert(this.presale.buy(alice, {from: alice, value: new BN(10)}), "isActive: sale is not active");
      })
    })
  })


  // describe('claim', function () {
  //   describe('when presale has not started', function() {
  //     beforeEach(async function () {
  //       await time.increaseTo(this.presale, startTime.subn(1));
  //     })
  //     it('reverts', async function() {
  //       await expectRevert(this.presale.claim(), "isClaimable: sale has not ended");
  //     })
  //   })
  //
  //   describe('when presale has started', function() {
  //     beforeEach(async function() {
  //       await time.increaseTo(this.presale, startTime)
  //     })
  //     it('reverts', async function() {
  //       await expectRevert(this.presale.claim(), "isClaimable: sale has not ended");
  //     })
  //   })
  //
  //   describe('when presale has ended without any purchase', function() {
  //     beforeEach(async function() {
  //       await time.increaseTo(this.presale, endTime)
  //       await this.presale.buildLP()
  //     })
  //     it('reverts', async function() {
  //       await expectRevert(this.presale.claim({from: alice}), "claim: zero allocation");
  //     })
  //   })
  //
  //   describe('when presale has ended with purchases', function() {
  //     beforeEach(async function() {
  //       await time.increaseTo(this.presale, startTime)
  //       await this.presale.buy(constants.ZERO_ADDRESS, {from: bob, value: new BN(100)})
  //       await time.increaseTo(this.presale, endTime)
  //     })
  //
  //     describe('when LP has not been built', function() {
  //       it('reverts', async function() {
  //         await expectRevert(this.presale.claim({from: bob}), "isClaimable: sale has not ended");
  //       })
  //     })
  //     describe('when LP has been built', function() {
  //       beforeEach(async function() {
  //         await this.presale.buildLP()
  //       })
  //
  //       describe('when user has not participated to the sale', function() {
  //         it('reverts', async function() {
  //           await expectRevert(this.presale.claim({from: alice}), "claim: zero allocation");
  //         })
  //       })
  //
  //       describe('when user has participated to the sale', function() {
  //         let userInfo
  //
  //         beforeEach(async function() {
  //           ({logs} = await this.presale.claim({from: bob}))
  //           userInfo = await this.presale.getUserInfo(bob)
  //         })
  //
  //         it('has updated user hasClaimed', async function() {
  //           expect(userInfo.hasClaimed).to.equal(true);
  //         })
  //
  //         it('has correct user balance', async function() {
  //           expect(await this.wftmToken.balanceOf(bob)).to.be.bignumber.equal(new BN(10))
  //         })
  //
  //         it('expect Claim event', async function() {
  //           expectEvent.inLogs(logs, 'Claim', {
  //             user: bob,
  //             lpAmount: new BN(10)
  //           });
  //         })
  //
  //         describe('when user has already claimed', function() {
  //           it('reverts', async function() {
  //             await expectRevert(this.presale.claim({from: bob}), "claim: already claimed");
  //           })
  //         })
  //       })
  //     })
  //   })
  // })

  describe('getUserShare', function () {})
})