# 四历史证明离线清理

原`gmsv/data/itemset.txt` SHA256 `c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d`，2282–2285行，第16列（零基）2771–2774，第78列均1。`char.c::CHAR_dropItemAtLogout`遍历角色随身物品，对`ITEM_DROPATLOGOUT`项移出并销毁；不按道具名字推断。

沿现项目2507–2517的角色load清理点，仅追加四个精确ID；普通snapshot/save不消失。同角色设备连接不等于角色load，未新增断线删除。仓库不在原随身遍历范围，本片未改其逻辑。全部重复实例清理，保其它物品UID与next_original_uid，不伪造END53。

`tools/test_transmigration_logout_source.py`实际核SHA/四行，1/1通过；`transmigration_logout_test`真实save/load及重复load七项0fail，日志`/private/tmp/stage-three-logout.log`。生产第三阶段目录激活与原监狱出口不在本片。
