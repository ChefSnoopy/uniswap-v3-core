# Uniswap V3 Bug Bounty

## Overview

Starting on March 23rd, 2021, the [uniswap-v3-core](https://github.com/Uniswap/uniswap-v3-core) repository is subject to the Uniswap V3 Bug Bounty (the "Program") to incentivize 
responsible bug disclosure.

We are limiting the scope of the Program to critical and high serverity bugs, and are offering a reward of up to $500,000. Happy hunting!

## Scope

The scope of the Program is limited to bugs that result in the draining of contract funds.

The following are not within the scope of the Program:

- Any contract located under [contracts/test](./contracts/test).
- Bugs in any third party contract or platform that interacts with Uniswap V3.
- Vulnerabilities already reported and/or discovered in contracts built by third parties on Uniswap V3.
- Any already-reported bugs.

Vulnerabilities contingent upon the occurrence of any of the following also are outside the scope of this Program:

- Frontend bugs
- DDOS attacks
- Spamming
- Phishing
- Automated tools (Github Actions, AWS, etc.)
- Compromise or misuse of third party systems or services