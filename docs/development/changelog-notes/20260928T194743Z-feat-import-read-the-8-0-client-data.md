---
subject: "feat(import): read the 8.0 client data"
title: "导入工具可读取 8.0 版客户端资料"
---

- 开发者工具：导入程序自动识别 2.5 与 8.0 客户端的资料文件（例如 adrn_136、PALET_1.SAP），2.5 的导入结果不变。
- ./scripts/setup-original-data.sh --with-8.0 会用 8.0 资料导入后期骑宠的人骑动画；不加此选项时，这些坐骑在导入清单中列为缺少素材。
