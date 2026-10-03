---
subject: "fix(pets): roll back warehouse transfers when saving fails"
title: "宠物存取保存失败时保持原位"
---

- 从宠物仓库或宠物大全取出宠物，以及将随身宠物存入仓库时，若存档保存失败，会提示重试，宠物仍保留在原处。
- 保存失败不会改变宠物属性、仓库顺序、出战与骑乘状态，也不会向其他设备发布成功状态；恢复保存后可重新操作。
