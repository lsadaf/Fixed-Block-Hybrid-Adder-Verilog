# Fixed Block Hybrid Adder (FBHA) – Verilog Implementation

This project provides a Verilog implementation of the **Fixed Block Hybrid Adder (FBHA)** architecture.

## Reference
The design is based on the paper:  
**"Design of Fixed Block Hybrid Adders"**  
[arXiv:2412.01764](https://arxiv.org/abs/2412.01764)

## Overview
The FBHA is a hybrid adder structure that divides the input width into:
- A **K-bit Carry-Lookahead Adder (CLA)** for the lower bits
- An **(N–K)-bit Carry-Select Adder (CSLA)** for the upper bits

This approach combines the fast carry computation of CLA with the parallel sum evaluation of CSLA, resulting in improved delay–area trade-offs compared to traditional adders.

## Current Configuration
- **Width (N):** 32 bits  
- **CLA size (K):** 24 bits (lower part)  
- **CSLA size:** 8 bits (upper part)  
- **CLA structure:** 8-4-4-4-2-2 hierarchy (from the paper’s best configuration)

## Files
- `FBHA.v` – Top-level FBHA implementation with supporting blocks:
  - Full Adder (FA)
  - Ripple-Carry Adder (RCA)
  - CLA modules (2, 4, 8, 24-bit)
  - Carry-Select Adder (8-bit)
