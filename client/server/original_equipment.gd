extends RefCounted
## Pinned itemset.txt; only explicitly reviewed ordinary equipment is wearable.
## Original HEAD/BODY coexist with legacy ownership, with one wearer per slot.
## arm / bracelet are
## CHAR_ARM / CHAR_DECORATION2, with amulets (legacy or original) in CHAR_DECORATION1.
const ITEMS := {
	# Reviewed second-stage rewards and carried quest equipment: fixed ordinary
	# fields only. Magic, resistances, multi-hit and throwing remain metadata.
	33:{"name":"贝所金Lv2斧头","type":1,"slot":"arm","level":20,"attack":24,"defence":-8,"speed":-8,"charm":0,"durability":200000}, # itemset:34
	36:{"name":"特洛金Lv2斧头","type":1,"slot":"arm","level":20,"attack":24,"defence":-8,"speed":-8,"charm":0,"durability":200000}, # itemset:37
	45:{"name":"特洛西Lv3斧头","type":1,"slot":"arm","level":25,"attack":30,"defence":-10,"speed":-10,"charm":0,"durability":200000}, # itemset:46
	46:{"name":"特洛西Lv3斧头","type":1,"slot":"arm","level":25,"attack":30,"defence":-10,"speed":-10,"charm":0,"durability":200000}, # itemset:47
	60:{"name":"强的斧头","type":1,"slot":"arm","level":35,"attack":43,"defence":-14,"speed":-14,"charm":0,"durability":300000}, # itemset:61
	65:{"name":"特洛西Lv4斧头","type":1,"slot":"arm","level":35,"attack":41,"defence":-13,"speed":-13,"charm":0,"durability":300000}, # itemset:66
	74:{"name":"莱伊萨Lv4斧头","type":1,"slot":"arm","level":40,"attack":47,"defence":-15,"speed":-15,"charm":0,"durability":300000}, # itemset:75
	75:{"name":"特洛金Lv4斧头","type":1,"slot":"arm","level":40,"attack":47,"defence":-15,"speed":-15,"charm":0,"durability":300000}, # itemset:76
	77:{"name":"特洛金Lv4斧头","type":1,"slot":"arm","level":40,"attack":47,"defence":-15,"speed":-15,"charm":0,"durability":300000}, # itemset:78
	78:{"name":"特洛金Lv4斧头","type":1,"slot":"arm","level":40,"attack":47,"defence":-15,"speed":-15,"charm":0,"durability":300000}, # itemset:79
	157:{"name":"特洛金Lv3棍棒","type":2,"slot":"arm","level":30,"attack":23,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:158
	160:{"name":"强的棍棒","type":2,"slot":"arm","level":35,"attack":28,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:161
	162:{"name":"威金娜斯Lv4棍棒","type":2,"slot":"arm","level":35,"attack":27,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:163
	165:{"name":"特洛西Lv4棍棒","type":2,"slot":"arm","level":35,"attack":27,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:166
	168:{"name":"特洛西Lv4棍棒","type":2,"slot":"arm","level":35,"attack":27,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:169
	170:{"name":"厉害的棍棒","type":2,"slot":"arm","level":40,"attack":32,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:171
	184:{"name":"莱伊卡Lv5棍棒","type":2,"slot":"arm","level":50,"attack":35,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:185
	185:{"name":"特洛西Lv5棍棒","type":2,"slot":"arm","level":50,"attack":35,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:186
	192:{"name":"威金娜斯Lv5棍棒","type":2,"slot":"arm","level":60,"attack":39,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:193
	193:{"name":"贝所金Lv5棍棒","type":2,"slot":"arm","level":60,"attack":39,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:194
	240:{"name":"大的枪","type":3,"slot":"arm","level":25,"attack":25,"defence":0,"speed":-5,"charm":3,"durability":200000}, # itemset:241
	244:{"name":"莱伊卡Lv3枪","type":3,"slot":"arm","level":25,"attack":23,"defence":0,"speed":-5,"charm":3,"durability":200000}, # itemset:245
	250:{"name":"硬的枪","type":3,"slot":"arm","level":30,"attack":30,"defence":0,"speed":-6,"charm":3,"durability":300000}, # itemset:251
	251:{"name":"贝洛萨Lv3枪","type":3,"slot":"arm","level":30,"attack":28,"defence":0,"speed":-6,"charm":3,"durability":300000}, # itemset:252
	255:{"name":"特洛金Lv3枪","type":3,"slot":"arm","level":30,"attack":28,"defence":0,"speed":-6,"charm":3,"durability":300000}, # itemset:256
	256:{"name":"特洛金Lv3枪","type":3,"slot":"arm","level":30,"attack":28,"defence":0,"speed":-6,"charm":3,"durability":300000}, # itemset:257
	257:{"name":"特洛金Lv3枪","type":3,"slot":"arm","level":30,"attack":28,"defence":0,"speed":-6,"charm":3,"durability":300000}, # itemset:258
	261:{"name":"贝诺美斯Lv4枪","type":3,"slot":"arm","level":35,"attack":33,"defence":0,"speed":-7,"charm":4,"durability":300000}, # itemset:262
	266:{"name":"特洛西Lv4枪","type":3,"slot":"arm","level":35,"attack":33,"defence":0,"speed":-7,"charm":4,"durability":300000}, # itemset:267
	282:{"name":"威金尼尔Lv5枪","type":3,"slot":"arm","level":50,"attack":43,"defence":0,"speed":-9,"charm":5,"durability":300000}, # itemset:283
	283:{"name":"迪所斯Lv5枪","type":3,"slot":"arm","level":50,"attack":43,"defence":0,"speed":-9,"charm":5,"durability":300000}, # itemset:284
	287:{"name":"特洛西Lv5枪","type":3,"slot":"arm","level":50,"attack":43,"defence":0,"speed":-9,"charm":5,"durability":300000}, # itemset:288
	288:{"name":"特洛西Lv5枪","type":3,"slot":"arm","level":50,"attack":43,"defence":0,"speed":-9,"charm":5,"durability":300000}, # itemset:289
	339:{"name":"特洛西Lv2爪","type":0,"slot":"arm","level":20,"attack":11,"defence":0,"speed":0,"charm":0,"durability":800000}, # itemset:340
	340:{"name":"大的爪","type":0,"slot":"arm","level":25,"attack":15,"defence":0,"speed":0,"charm":0,"durability":800000}, # itemset:341
	344:{"name":"莱伊卡Lv3爪","type":0,"slot":"arm","level":25,"attack":14,"defence":0,"speed":0,"charm":0,"durability":800000}, # itemset:345
	345:{"name":"特洛西Lv3爪","type":0,"slot":"arm","level":25,"attack":14,"defence":0,"speed":0,"charm":0,"durability":800000}, # itemset:346
	356:{"name":"特洛金Lv3爪","type":0,"slot":"arm","level":30,"attack":17,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:357
	359:{"name":"特洛金Lv3爪","type":0,"slot":"arm","level":30,"attack":17,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:360
	364:{"name":"莱伊卡Lv4爪","type":0,"slot":"arm","level":35,"attack":20,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:365
	378:{"name":"特洛金Lv4爪","type":0,"slot":"arm","level":40,"attack":23,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:379
	379:{"name":"特洛金Lv4爪","type":0,"slot":"arm","level":40,"attack":23,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:380
	383:{"name":"迪所斯Lv5爪","type":0,"slot":"arm","level":50,"attack":26,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:384
	384:{"name":"莱伊卡Lv5爪","type":0,"slot":"arm","level":50,"attack":26,"defence":0,"speed":0,"charm":0,"durability":1200000}, # itemset:385
	440:{"name":"大的弓箭","type":4,"slot":"arm","level":30,"attack":10,"defence":-9,"speed":0,"charm":0,"durability":800000}, # itemset:441
	442:{"name":"威金尼尔Lv3弓箭","type":4,"slot":"arm","level":30,"attack":10,"defence":-10,"speed":0,"charm":0,"durability":800000}, # itemset:443
	443:{"name":"迪所斯Lv3弓箭","type":4,"slot":"arm","level":30,"attack":10,"defence":-10,"speed":0,"charm":0,"durability":800000}, # itemset:444
	453:{"name":"贝所金Lv3弓箭","type":4,"slot":"arm","level":35,"attack":12,"defence":-12,"speed":0,"charm":0,"durability":1200000}, # itemset:454
	457:{"name":"特洛金Lv3弓箭","type":4,"slot":"arm","level":35,"attack":12,"defence":-12,"speed":0,"charm":0,"durability":1200000}, # itemset:458
	458:{"name":"特洛金Lv3弓箭","type":4,"slot":"arm","level":35,"attack":12,"defence":-12,"speed":0,"charm":0,"durability":1200000}, # itemset:459
	459:{"name":"特洛金Lv3弓箭","type":4,"slot":"arm","level":50,"attack":18,"defence":-18,"speed":0,"charm":0,"durability":1200000}, # itemset:460
	477:{"name":"特洛金Lv4弓箭","type":4,"slot":"arm","level":45,"attack":16,"defence":-16,"speed":0,"charm":0,"durability":1200000}, # itemset:478
	478:{"name":"特洛金Lv4弓箭","type":4,"slot":"arm","level":45,"attack":16,"defence":-16,"speed":0,"charm":0,"durability":1200000}, # itemset:479
	485:{"name":"特洛西Lv5弓箭","type":4,"slot":"arm","level":50,"attack":18,"defence":-18,"speed":0,"charm":0,"durability":1200000}, # itemset:486
	486:{"name":"特洛西Lv5弓箭","type":4,"slot":"arm","level":50,"attack":18,"defence":-18,"speed":0,"charm":0,"durability":1200000}, # itemset:487
	530:{"name":"重的回旋标","type":17,"slot":"arm","level":25,"attack":13,"defence":0,"speed":-1,"charm":3,"durability":800000}, # itemset:531
	532:{"name":"威金娜斯Lv2回旋标","type":17,"slot":"arm","level":25,"attack":11,"defence":0,"speed":0,"charm":1,"durability":800000}, # itemset:533
	540:{"name":"大的回旋标","type":17,"slot":"arm","level":30,"attack":15,"defence":0,"speed":0,"charm":4,"durability":800000}, # itemset:541
	542:{"name":"威金尼尔Lv3回旋标","type":17,"slot":"arm","level":30,"attack":14,"defence":0,"speed":0,"charm":2,"durability":800000}, # itemset:543
	544:{"name":"莱伊卡Lv3回旋标","type":17,"slot":"arm","level":30,"attack":14,"defence":0,"speed":0,"charm":2,"durability":800000}, # itemset:545
	558:{"name":"特洛金Lv3回旋标","type":17,"slot":"arm","level":35,"attack":16,"defence":0,"speed":0,"charm":2,"durability":1200000}, # itemset:559
	561:{"name":"贝诺美斯Lv4回旋标","type":17,"slot":"arm","level":40,"attack":18,"defence":0,"speed":0,"charm":2,"durability":1200000}, # itemset:562
	562:{"name":"威金尼尔Lv4回旋标","type":17,"slot":"arm","level":40,"attack":18,"defence":0,"speed":0,"charm":2,"durability":1200000}, # itemset:563
	578:{"name":"特洛金Lv4回旋标","type":17,"slot":"arm","level":45,"attack":20,"defence":0,"speed":0,"charm":3,"durability":1200000}, # itemset:579
	579:{"name":"特洛金Lv4回旋标","type":17,"slot":"arm","level":45,"attack":20,"defence":0,"speed":0,"charm":3,"durability":1200000}, # itemset:580
	584:{"name":"莱伊卡Lv5回旋标","type":17,"slot":"arm","level":50,"attack":22,"defence":0,"speed":0,"charm":3,"durability":1200000}, # itemset:585
	585:{"name":"特洛西Lv5回旋标","type":17,"slot":"arm","level":50,"attack":22,"defence":0,"speed":0,"charm":3,"durability":1200000}, # itemset:586
	645:{"name":"特洛西Lv3投掷斧头","type":18,"slot":"arm","level":25,"attack":19,"defence":0,"speed":0,"charm":0,"durability":200000}, # itemset:646
	646:{"name":"特洛西Lv3投掷斧头","type":18,"slot":"arm","level":25,"attack":19,"defence":0,"speed":0,"charm":0,"durability":200000}, # itemset:647
	652:{"name":"威金娜斯Lv3投掷斧头","type":18,"slot":"arm","level":30,"attack":23,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:653
	655:{"name":"特洛金Lv3投掷斧头","type":18,"slot":"arm","level":30,"attack":23,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:656
	664:{"name":"莱伊卡Lv4投掷斧头","type":18,"slot":"arm","level":35,"attack":27,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:665
	667:{"name":"特洛西Lv4投掷斧头","type":18,"slot":"arm","level":35,"attack":27,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:668
	676:{"name":"特洛金Lv4投掷斧头","type":18,"slot":"arm","level":40,"attack":31,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:677
	677:{"name":"特洛金Lv4投掷斧头","type":18,"slot":"arm","level":40,"attack":31,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:678
	681:{"name":"贝诺美斯Lv5投掷斧头","type":18,"slot":"arm","level":50,"attack":35,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:682
	682:{"name":"威金尼尔Lv5投掷斧头","type":18,"slot":"arm","level":50,"attack":35,"defence":0,"speed":0,"charm":0,"durability":300000}, # itemset:683
	743:{"name":"迪所斯Lv3石","type":19,"slot":"arm","level":25,"attack":14,"defence":-3,"speed":0,"charm":0,"durability":200000}, # itemset:744
	745:{"name":"特洛西Lv3石","type":19,"slot":"arm","level":25,"attack":14,"defence":-3,"speed":0,"charm":0,"durability":200000}, # itemset:746
	747:{"name":"特洛西Lv3石","type":19,"slot":"arm","level":25,"attack":14,"defence":-3,"speed":0,"charm":0,"durability":200000}, # itemset:748
	750:{"name":"硬的石","type":19,"slot":"arm","level":30,"attack":18,"defence":-3,"speed":0,"charm":0,"durability":300000}, # itemset:751
	751:{"name":"贝洛萨Lv3石","type":19,"slot":"arm","level":30,"attack":17,"defence":-3,"speed":0,"charm":0,"durability":300000}, # itemset:752
	755:{"name":"特洛金Lv3石","type":19,"slot":"arm","level":30,"attack":17,"defence":-3,"speed":0,"charm":0,"durability":300000}, # itemset:756
	758:{"name":"特洛金Lv3石","type":19,"slot":"arm","level":30,"attack":17,"defence":-3,"speed":0,"charm":0,"durability":300000}, # itemset:759
	773:{"name":"贝所金Lv4石","type":19,"slot":"arm","level":40,"attack":23,"defence":-4,"speed":0,"charm":0,"durability":300000}, # itemset:774
	774:{"name":"莱伊萨Lv4石","type":19,"slot":"arm","level":40,"attack":23,"defence":-4,"speed":0,"charm":0,"durability":300000}, # itemset:775
	782:{"name":"威金尼尔Lv5石","type":19,"slot":"arm","level":50,"attack":26,"defence":-5,"speed":0,"charm":0,"durability":300000}, # itemset:783
	783:{"name":"迪所斯Lv5石","type":19,"slot":"arm","level":50,"attack":26,"defence":-5,"speed":0,"charm":0,"durability":300000}, # itemset:784
	874:{"name":"渥鲁菲Lv1兜8","type":6,"slot":"head","level":40,"attack":0,"defence":14,"speed":-4,"charm":0,"durability":300000}, # itemset:875
	875:{"name":"米鲁菲Lv1兜8","type":6,"slot":"head","level":40,"attack":0,"defence":14,"speed":-4,"charm":0,"durability":300000}, # itemset:876
	877:{"name":"米鲁菲Lv1兜8","type":6,"slot":"head","level":40,"attack":0,"defence":14,"speed":-4,"charm":0,"durability":300000}, # itemset:878
	878:{"name":"米鲁菲Lv1兜8","type":6,"slot":"head","level":40,"attack":0,"defence":14,"speed":-4,"charm":0,"durability":300000}, # itemset:879
	957:{"name":"米鲁菲Lv2帽子6","type":6,"slot":"head","level":30,"attack":0,"defence":5,"speed":0,"charm":0,"durability":300000}, # itemset:958
	964:{"name":"渥鲁菲Lv2帽子7","type":6,"slot":"head","level":35,"attack":0,"defence":6,"speed":0,"charm":0,"durability":300000}, # itemset:965
	966:{"name":"米鲁菲Lv2帽子7","type":6,"slot":"head","level":35,"attack":0,"defence":6,"speed":0,"charm":0,"durability":300000}, # itemset:967
	970:{"name":"厉害的帽子","type":6,"slot":"head","level":40,"attack":0,"defence":8,"speed":0,"charm":0,"durability":300000}, # itemset:971
	971:{"name":"美鲁菲Lv2帽子8","type":6,"slot":"head","level":40,"attack":0,"defence":7,"speed":0,"charm":0,"durability":300000}, # itemset:972
	975:{"name":"米鲁菲Lv2帽子8","type":6,"slot":"head","level":40,"attack":0,"defence":7,"speed":0,"charm":0,"durability":300000}, # itemset:976
	976:{"name":"米鲁菲Lv2帽子8","type":6,"slot":"head","level":40,"attack":0,"defence":7,"speed":0,"charm":0,"durability":300000}, # itemset:977
	982:{"name":"爱鲁菲Lv2帽子9","type":6,"slot":"head","level":50,"attack":0,"defence":8,"speed":0,"charm":0,"durability":300000}, # itemset:983
	983:{"name":"所鲁菲Lv2帽子9","type":6,"slot":"head","level":50,"attack":0,"defence":8,"speed":0,"charm":0,"durability":300000}, # itemset:984
	1034:{"name":"哈鲁Lv2铠4","type":7,"slot":"body","level":20,"attack":0,"defence":15,"speed":-4,"charm":0,"durability":200000}, # itemset:1035
	1036:{"name":"提欧Lv2铠4","type":7,"slot":"body","level":20,"attack":0,"defence":14,"speed":-4,"charm":0,"durability":200000}, # itemset:1037
	1044:{"name":"哈鲁Lv2铠5","type":7,"slot":"body","level":25,"attack":0,"defence":19,"speed":-5,"charm":0,"durability":200000}, # itemset:1045
	1045:{"name":"芙雷雅Lv2铠5","type":7,"slot":"body","level":25,"attack":0,"defence":18,"speed":-5,"charm":0,"durability":200000}, # itemset:1046
	1047:{"name":"提欧Lv2铠5","type":7,"slot":"body","level":25,"attack":0,"defence":18,"speed":-5,"charm":0,"durability":200000}, # itemset:1048
	1056:{"name":"提欧Lv2铠6","type":7,"slot":"body","level":30,"attack":0,"defence":21,"speed":-6,"charm":0,"durability":300000}, # itemset:1057
	1064:{"name":"哈鲁Lv2铠7","type":7,"slot":"body","level":35,"attack":0,"defence":26,"speed":-7,"charm":0,"durability":300000}, # itemset:1065
	1065:{"name":"芙雷雅Lv2铠7","type":7,"slot":"body","level":35,"attack":0,"defence":25,"speed":-7,"charm":0,"durability":300000}, # itemset:1066
	1069:{"name":"提欧Lv3铠7","type":7,"slot":"body","level":35,"attack":0,"defence":26,"speed":-7,"charm":0,"durability":300000}, # itemset:1070
	1070:{"name":"厉害的铠","type":7,"slot":"body","level":40,"attack":0,"defence":32,"speed":-8,"charm":0,"durability":300000}, # itemset:1071
	1141:{"name":"哈鲁Lv1服5","type":7,"slot":"body","level":25,"attack":0,"defence":10,"speed":0,"charm":0,"durability":200000}, # itemset:1142
	1144:{"name":"哈鲁Lv2服5","type":7,"slot":"body","level":25,"attack":0,"defence":11,"speed":0,"charm":0,"durability":200000}, # itemset:1145
	1154:{"name":"哈鲁Lv2服6","type":7,"slot":"body","level":30,"attack":0,"defence":13,"speed":0,"charm":0,"durability":300000}, # itemset:1155
	1156:{"name":"提欧Lv2服6","type":7,"slot":"body","level":30,"attack":0,"defence":13,"speed":0,"charm":0,"durability":300000}, # itemset:1157
	1159:{"name":"提欧Lv3服6","type":7,"slot":"body","level":30,"attack":0,"defence":14,"speed":0,"charm":0,"durability":300000}, # itemset:1160
	1165:{"name":"芙雷雅Lv2服7","type":7,"slot":"body","level":35,"attack":0,"defence":15,"speed":0,"charm":0,"durability":300000}, # itemset:1166
	1168:{"name":"芙雷雅Lv3服7","type":7,"slot":"body","level":35,"attack":0,"defence":16,"speed":0,"charm":0,"durability":300000}, # itemset:1169
	1169:{"name":"提欧Lv3服7","type":7,"slot":"body","level":35,"attack":0,"defence":16,"speed":0,"charm":0,"durability":300000}, # itemset:1170
	1172:{"name":"芙雷雅Lv1服8","type":7,"slot":"body","level":40,"attack":0,"defence":17,"speed":0,"charm":0,"durability":300000}, # itemset:1173
	1173:{"name":"提欧Lv1服8","type":7,"slot":"body","level":40,"attack":0,"defence":17,"speed":0,"charm":0,"durability":300000}, # itemset:1174
	1269:{"name":"阿鲁帖拉鸣子","type":9,"slot":"amulet","level":35,"attack":0,"defence":0,"speed":0,"charm":3,"durability":300000}, # itemset:1264
	1352:{"name":"小骨首饰","type":10,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":1,"durability":200000}, # itemset:1343
	1358:{"name":"黑色大首饰","type":10,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":5,"durability":200000}, # itemset:1349
	1359:{"name":"青色大首饰","type":10,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":5,"durability":200000}, # itemset:1350
	1367:{"name":"青石首饰","type":10,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":5,"durability":200000}, # itemset:1358
	1451:{"name":"柯雅拉Lv2护身符","type":15,"slot":"amulet","level":10,"attack":0,"defence":0,"speed":0,"charm":2,"durability":300000}, # itemset:1429
	1460:{"name":"美丽尼亚护身符1","type":15,"slot":"amulet","level":10,"attack":0,"defence":0,"speed":0,"charm":1,"durability":300000}, # itemset:1438
	1466:{"name":"威鲁护身符2","type":15,"slot":"amulet","level":20,"attack":0,"defence":0,"speed":0,"charm":2,"durability":300000}, # itemset:1444
	2691:{"name":"芙蕾美雅Lv3的戒指","type":11,"slot":"amulet","level":50,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2213
	2692:{"name":"哈鲁Lv3的戒指","type":11,"slot":"amulet","level":50,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2214
	2693:{"name":"迪欧Lv2的戒指","type":11,"slot":"amulet","level":50,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2215
	2694:{"name":"芙蕾美雅Lv3的手镯","type":8,"slot":"bracelet","level":50,"attack":-1,"defence":1,"speed":0,"charm":1,"durability":0}, # itemset:2216
	2695:{"name":"哈鲁Lv3的手镯","type":8,"slot":"bracelet","level":50,"attack":2,"defence":-1,"speed":0,"charm":2,"durability":0}, # itemset:2217
	2696:{"name":"迪欧Lv2的戒指","type":11,"slot":"amulet","level":50,"attack":2,"defence":-2,"speed":0,"charm":3,"durability":0}, # itemset:2218
	2699:{"name":"拉鲁的项链","type":10,"slot":"amulet","level":55,"attack":0,"defence":0,"speed":0,"charm":2,"durability":0}, # itemset:2221
	2700:{"name":"大地之羽[地]","type":15,"slot":"amulet","level":55,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2222
	2701:{"name":"大地的羁绊[地]","type":10,"slot":"amulet","level":55,"attack":-4,"defence":5,"speed":0,"charm":3,"durability":300000}, # itemset:2223
	2706:{"name":"不死鸟的羽毛[火]","type":15,"slot":"amulet","level":55,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2228
	2707:{"name":"火的羽毛饰品[火]","type":10,"slot":"amulet","level":55,"attack":2,"defence":-7,"speed":5,"charm":3,"durability":300000}, # itemset:2229
	2766:{"name":"水苍之贝 [水]","type":15,"slot":"amulet","level":65,"attack":0,"defence":0,"speed":0,"charm":3,"durability":0}, # itemset:2277
	2770:{"name":"水的戒指[水]","type":11,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":3,"durability":300000}, # itemset:2281
	# itemset.txt:1053: fixed ordinary modifiers; magic 10 remains metadata.
	1052:{"name":"芙雷雅Lv1铠6","type":7,"slot":"body","level":30,"attack":0,"defence":20,"speed":-6,"charm":0,"durability":2500000},
	# Dream cave source ordinary fields; magic and sleep resistance remain metadata.
	2605:{"name":"空想的帽子","type":6,"slot":"head","level":35,"attack":0,"defence":4,"speed":2,"charm":0,"durability":2500000},
	2606:{"name":"空想的竖琴","type":9,"slot":"amulet","level":35,"attack":2,"defence":0,"speed":1,"charm":5,"durability":2500000},
	# itemset.txt:2070, item.h:25/item.c:1242-1245: EARRING uses DECORATION1.
	2487:{"name":"母亲的发饰","type":13,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":2,"durability":200000},
	# Dragon cave itemset.txt:2043,2088; existing ARM/amulet ordinary modifiers.
	2460:{"name":"龙之枪","type":3,"slot":"arm","level":40,"attack":36,"defence":-14,"speed":-14,"charm":2,"durability":2500000},
	2505:{"name":"龙的魅力之笛","type":9,"slot":"amulet","level":40,"attack":0,"defence":0,"speed":0,"charm":3,"durability":200000},
	# itemset.txt:1348,2072,2074-2077; fixed ordinary modifiers only.
	1357:{"name":"黄色大首饰","type":10,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":5,"durability":2500000},
	2489:{"name":"卡娜的木笛","type":9,"slot":"amulet","level":0,"attack":0,"defence":0,"speed":0,"charm":2,"durability":2500000},
	2491:{"name":"山贼的手环","type":8,"slot":"bracelet","level":40,"attack":0,"defence":0,"speed":0,"charm":0,"durability":300000},
	2492:{"name":"山贼的投掷斧头","type":18,"slot":"arm","level":40,"attack":20,"defence":-5,"speed":0,"charm":5,"durability":200000},
	2493:{"name":"山贼的爪","type":0,"slot":"arm","level":40,"attack":17,"defence":-5,"speed":0,"charm":5,"durability":300000},
	2494:{"name":"山贼的小棍棒","type":2,"slot":"arm","level":40,"attack":7,"defence":0,"speed":0,"charm":5,"durability":200000},
	# itemset.txt:2276; original revival guardian magic remains metadata only.
	2765:{"name":"月光的手镯","type":8,"slot":"bracelet","level":60,"attack":3,"defence":3,"speed":-3,"charm":1,"durability":2500000},
	# itemset.txt:2210–2212; original magic remains metadata only.
	2688:{"name":"马祖的斧头","type":1,"slot":"arm","level":50,"attack":50,"defence":-20,"speed":-20,"charm":0,"durability":2500000},
	2689:{"name":"马祖的矛","type":3,"slot":"arm","level":50,"attack":45,"defence":0,"speed":-10,"charm":4,"durability":2500000},
	2690:{"name":"马祖的棍棒","type":2,"slot":"arm","level":50,"attack":35,"defence":0,"speed":0,"charm":0,"durability":2500000},
	# itemset.txt:1207 numeric fields override its stale +2/+2/-2/+1 prose.
	1206:{"name":"红玉的手环","type":8,"slot":"bracelet","level":0,"attack":3,"defence":3,"speed":-3,"charm":2,"durability":2500000},
	# itemset.txt:1999/2031; the delivery axe is usable from Lv20.
	2416:{"name":"亚姆亚姆的斧头","type":1,"slot":"arm","level":20,"attack":9,"defence":-3,"speed":-3,"charm":0,"durability":0},
	2448:{"name":"亚姆亚姆的斧头","type":1,"slot":"arm","level":25,"attack":35,"defence":-10,"speed":-10,"charm":0,"durability":2500000},
	2418:{"name":"仪之兜","type":6,"slot":"head","level":30,"attack":0,"defence":15,"speed":-3,"charm":0,"durability":2500000,"resistances":[3,3,3,3,3,3]},
	2427:{"name":"老爷爷的护身符","type":15,"slot":"amulet","level":10,"attack":0,"defence":0,"speed":0,"charm":-1,"durability":2500000,"resistances":[2,2,2,2,2,2]},
	2465:{"name":"哈恩的斧头","type":1,"slot":"arm","level":25,"attack":35,"defence":-15,"speed":-15,"charm":0,"durability":0},
	2485:{"name":"哈恩改造的斧头","type":1,"slot":"arm","level":25,"attack":33,"defence":-10,"speed":-10,"charm":0,"durability":300000},
	2481:{"name":"杉的手环","type":8,"slot":"bracelet","level":30,"attack":8,"defence":5,"speed":-5,"charm":-5,"durability":2500000},
}
## These formerly metadata-only items may exist with zero durability, unworn.
const NEWLY_WEARABLE := [1357,2460,2487,2489,2491,2492,2493,2494,2505,2605,2606,
	33,36,45,46,60,65,74,75,77,78,157,160,162,165,168,170,184,185,192,193,240,244,250,251,255,256,257,261,266,282,283,287,288,339,340,344,345,356,359,364,378,379,383,384,440,442,443,453,457,458,459,477,478,485,486,530,532,540,542,544,558,561,562,578,579,584,585,645,646,652,655,664,667,676,677,681,682,743,745,747,750,751,755,758,773,774,782,783,874,875,877,878,957,964,966,970,971,975,976,982,983,1034,1036,1044,1045,1047,1056,1064,1065,1069,1070,1141,1144,1154,1156,1159,1165,1168,1169,1172,1173,1269,1352,1358,1359,1367,1451,1460,1466,2701,2707,2770]
const STAGES := ["完好","受损","毁坏","不堪使用"]
const STATS := ["attack","defence","speed","charm"]

static func instance(id: int, uid: int) -> Dictionary:
	return {"uid":uid,"item_id":id,"durability":int(ITEMS.get(id,{}).get("durability",0))}

static func migrate(profile: Dictionary) -> void:
	if profile.has("original_instances"):
		if not profile.original_equipment.has("body"):
			profile.original_equipment.body=0
			for entry in profile.original_instances:
				if int(entry.item_id)==1052 and int(entry.durability)==0:entry.durability=2500000
		for entry in profile.original_instances:
			if int(entry.item_id) in NEWLY_WEARABLE and int(entry.durability)==0 and not worn(profile,int(entry.uid)):
				entry.durability=int(ITEMS[int(entry.item_id)].durability)
		# Version 6 used no HEAD field: 2418 was an unworn story instance
		# with zero durability. Initialize that newly supported item only once.
		if not profile.original_equipment.has("head"):
			profile.original_equipment.head=0
			for entry in profile.original_instances:
				if int(entry.item_id)==2418 and int(entry.durability)==0:entry.durability=2500000
		# original_items remains the canonical compatibility projection. Old
		# authority tools may append it directly; retain existing copies in order
		# and initialize only newly acquired entries, never re-roll durability.
		if profile.original_instances.size()==profile.get("original_items",[]).size():
			var aligned:=true
			for i in range(profile.original_instances.size()):
				if int(profile.original_instances[i].item_id)!=int(profile.original_items[i]):aligned=false;break
			if aligned:return
		var existing: Array=profile.original_instances.duplicate()
		var rebuilt: Array=[]
		for id in profile.get("original_items",[]):
			var index: int=-1
			for i in range(existing.size()):
				if int(existing[i].item_id)==int(id):index=i;break
			if index>=0:rebuilt.append(existing.pop_at(index))
			else:
				rebuilt.append(instance(int(id),int(profile.next_original_uid)))
				profile.next_original_uid+=1
		profile.original_instances=rebuilt
		var uids: Array=rebuilt.map(func(entry):return int(entry.uid))
		for slot in profile.original_equipment:
			if int(profile.original_equipment[slot]) not in uids:profile.original_equipment[slot]=0
		return
	profile.original_instances=[]
	profile.original_equipment={"arm":0,"bracelet":0,"amulet":0,"head":0,"body":0}
	profile.next_original_uid=1
	for id in profile.get("original_items",[]):
		profile.original_instances.append(instance(int(id),int(profile.next_original_uid)))
		profile.next_original_uid+=1

static func add(profile: Dictionary, id: int) -> void:
	migrate(profile)
	profile.original_items.append(id)
	profile.original_instances.append(instance(id,int(profile.next_original_uid)))
	profile.next_original_uid+=1

static func remove_at(profile: Dictionary, index: int) -> void:
	migrate(profile)
	if index<0 or index>=profile.original_items.size():return
	var uid: int=int(profile.original_instances[index].uid)
	for slot in profile.original_equipment:
		if int(profile.original_equipment[slot])==uid:profile.original_equipment[slot]=0
	profile.original_instances.remove_at(index)
	profile.original_items.remove_at(index)

static func remove(profile: Dictionary, id: int) -> void:
	migrate(profile)
	# Original NPC scans start at equipped positions before the bag. A script that
	# consumes one copy therefore consumes the worn copy first, if present.
	for i in range(profile.original_instances.size()):
		var entry: Dictionary=profile.original_instances[i]
		if int(entry.item_id)==id and worn(profile,int(entry.uid)):
			remove_at(profile,i)
			return
	remove_at(profile,profile.original_items.find(id))

static func worn(profile: Dictionary, uid: int) -> bool:
	return uid>0 and profile.get("original_equipment",{}).values().any(func(value):return integer(value,1,2147483647) and int(value)==uid)

static func mods(profile: Dictionary) -> Dictionary:
	var result: Dictionary={"attack":0,"defence":0,"speed":0,"charm":0}
	for entry in profile.get("original_instances",[]):
		if not worn(profile,int(entry.uid)):continue
		for stat in STATS:result[stat]+=int(ITEMS[int(entry.item_id)][stat])
	return result

## itemset six resistance modifiers: poison, paralysis, sleep, stone,
## drunk, confusion. Metadata only until the battle status system exists.
static func resistances(profile: Dictionary) -> Array:
	var result: Array=[0,0,0,0,0,0]
	for entry in profile.get("original_instances",[]):
		if not worn(profile,int(entry.uid)):continue
		var values: Array=ITEMS[int(entry.item_id)].get("resistances",[0,0,0,0,0,0])
		for i in range(6):result[i]+=int(values[i])
	return result

static func battle_items(profile: Dictionary) -> Array:
	var result: Array=[]
	for entry in profile.get("original_instances",[]):
		if worn(profile,int(entry.uid)):result.append(entry.duplicate(true))
	return result

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and float(value)==floor(float(value)) and value>=low and value<=high

static func valid(profile: Dictionary) -> bool:
	if profile.has("equipment") and not profile.equipment is Dictionary:return false
	if not profile.get("original_instances") is Array or profile.original_instances.size()!=profile.original_items.size():return false
	if not profile.get("original_equipment") is Dictionary:return false
	var has_head: bool=profile.original_equipment.has("head")
	var has_body: bool=profile.original_equipment.has("body")
	if has_body and not has_head:return false
	if profile.original_equipment.size()!=3+int(has_head)+int(has_body):return false
	if not integer(profile.get("next_original_uid"),1,2147483647):return false
	var seen: Array=[]
	for i in range(profile.original_instances.size()):
		var entry=profile.original_instances[i]
		if not entry is Dictionary or entry.size()!=3 or not integer(entry.get("uid"),1,int(profile.next_original_uid)-1) or entry.uid in seen:return false
		if not integer(entry.get("item_id"),1,2147483647) or int(entry.item_id)!=int(profile.original_items[i]):return false
		if not integer(entry.get("durability"),0,int(ITEMS.get(int(entry.item_id),{}).get("durability",0))):return false
		var legacy_helmet: bool=(int(entry.item_id)==2418 and not has_head) or (int(entry.item_id)==1052 and not has_body)
		if legacy_helmet and int(entry.durability)!=0:return false
		if not legacy_helmet and ITEMS.has(int(entry.item_id)) and int(ITEMS[int(entry.item_id)].durability)>0 and int(entry.durability)==0:
			if int(entry.item_id) not in NEWLY_WEARABLE or worn(profile,int(entry.uid)):return false
		seen.append(entry.uid)
	var slots: Array=["arm","bracelet","amulet"]
	if has_head:slots.append("head")
	if has_body:slots.append("body")
	for slot in slots:
		var uid=profile.original_equipment.get(slot)
		if not integer(uid,0,int(profile.next_original_uid)-1):return false
		if int(uid)==0:continue
		var matches: Array=profile.original_instances.filter(func(entry):return int(entry.uid)==int(uid))
		if matches.size()!=1 or not ITEMS.has(int(matches[0].item_id)) or str(ITEMS[int(matches[0].item_id)].slot)!=slot:return false
		if slot=="body":
			if not profile.get("player") is Dictionary or not integer(profile.player.get("level"),int(ITEMS[int(matches[0].item_id)].level),1000000):return false
	if has_body and int(profile.original_equipment.body)>0 and not str(profile.get("equipment",{}).get("body","")).is_empty():return false
	if int(profile.original_equipment.arm)>0 and bool(profile.get("equipped",false)):return false
	if int(profile.original_equipment.amulet)>0 and (bool(profile.get("equipped_mirror",false)) or not str(profile.get("equipment",{}).get("amulet","")).is_empty()):return false
	return true

## Validate a settlement against the equipment at admission, before mutation.
static func result_valid(initial: Array, final: Variant) -> bool:
	if not final is Array or initial.size()!=final.size():return false
	for i in range(initial.size()):
		var entry=final[i]
		if not entry is Dictionary or entry.size()!=3:return false
		if entry.get("uid")!=initial[i].uid or entry.get("item_id")!=initial[i].item_id or not integer(entry.get("durability"),0,int(initial[i].durability)):return false
	return true

static func settle(profile: Dictionary, final: Array) -> void:
	for entry in final:
		for index in range(profile.original_instances.size()):
			if int(profile.original_instances[index].uid)!=int(entry.uid):continue
			if int(entry.durability)==0 and int(ITEMS[int(entry.item_id)].durability)>0:remove_at(profile,index)
			else:profile.original_instances[index].durability=int(entry.durability)
			break

## BATTLE_ItemCrush: preserve C integer truncation and its overwritten >=200
## assignment. RAND is the original inclusive floating upper-bound macro.
static func wear_amount(damage: int, arm: bool, rng: RandomNumberGenerator) -> int:
	var low:=int((damage-50)/40) if arm else int((200-damage)/20)
	if (arm and low<=0) or (not arm and low<0):low=1
	return low+int((float(low)*1.4-float(low)+1.0)*float(rng.randi() & 0x7fffffff)/2147483648.0)

static func stage(entry: Dictionary) -> int:
	var maximum:=int(ITEMS[int(entry.item_id)].durability)
	if maximum<1:return 0
	var percent:=int(int(entry.durability)*100/maximum)
	return 0 if percent>=70 else 1 if percent>=50 else 2 if percent>=30 else 3
