---
subject: "fix(hunt): weaken a target first when a capture cannot win yet"
title: "捕获率太低时先削血再抓"
---

- 自动抓宠满血时捕获率不足10%的宠物（如斑尼迪克）会先用削血宠削血，不再一直丢、永远抓不到。
- 没有可用削血宠且捕获率为0时停下并写明原因。
