// Matrix-management fixtures captured from a real device (WLED 16.0.1, ESP32,
// 16x16) on 2026-10-02. The config is trimmed to the parts the app reads.

/// /presets.json: a GIF state preset (1), an "off" preset (101) and a preset
/// saved by the WLED UI (102).
const presetsV16 = r'''{"0":{},"101":{"on":false,"n":"WLED Turn Off"},"102":{"seg":[{"n":"pipplee.gif","bri":128,"sx":64,"id":0,"fx":53,"frz":false,"fxdef":true,"col":[[0,0,0]],"start":0,"stop":16,"startY":0,"stopY":16},{"id":1,"stop":0},{"id":2,"stop":0},{"id":3,"stop":0}],"on":true,"n":"pipplee.gif"},"1":{"on":true,"bri":128,"transition":7,"bs":0,"mainseg":0,"seg":[{"id":0,"start":0,"stop":16,"startY":0,"stopY":16,"grp":1,"spc":0,"of":0,"on":true,"frz":false,"bri":128,"cct":127,"set":0,"lc":1,"n":"ocean-plasma.gif","col":[[0,0,0],[0,0,0],[0,0,0]],"fx":53,"sx":128,"ix":0,"pal":0,"c1":128,"c2":128,"c3":16,"sel":true,"rev":false,"mi":false,"rY":false,"mY":false,"tp":false,"o1":false,"o2":false,"o3":false,"si":0,"m12":0,"bm":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0},{"stop":0}],"n":"Ocean Plasma"}}''';

/// /json/state while preset 102 plays.
const stateV16 = r'''{"on":true,"bri":128,"transition":7,"bs":0,"ps":102,"pl":-1,"ledmap":0,"AudioReactive":{"on":false},"nl":{"on":false,"dur":60,"mode":1,"tbri":0,"rem":-1},"udpn":{"send":false,"recv":true,"sgrp":1,"rgrp":1},"lor":0,"mainseg":0,"seg":[{"id":0,"start":0,"stop":16,"startY":0,"stopY":16,"len":16,"grp":1,"spc":0,"of":0,"on":true,"frz":false,"bri":128,"cct":127,"set":0,"lc":1,"n":"pipplee.gif","col":[[0,0,0],[0,0,0],[0,0,0]],"fx":53,"sx":64,"ix":0,"pal":0,"c1":128,"c2":128,"c3":16,"sel":true,"rev":false,"mi":false,"rY":false,"mY":false,"tp":false,"o1":false,"o2":false,"o3":false,"si":0,"m12":0,"bm":0}]}''';

/// /edit?list=/
const filesV16 = r'''[{"name":"bkp.cfg.json","type":"file","size":2614},{"name":"cfg.json","type":"file","size":2613},{"name":"duck.gif","type":"file","size":142},{"name":"fontfactory.htm.gz","type":"file","size":8464},{"name":"goose.gif","type":"file","size":142},{"name":"mypaint.gif","type":"file","size":142},{"name":"ocean-plasma.gif","type":"file","size":24291},{"name":"pftools.json","type":"file","size":1099},{"name":"pipplee.gif","type":"file","size":14527},{"name":"pixelpaint.htm.gz","type":"file","size":11506},{"name":"presets.json","type":"file","size":1075},{"name":"pxmagic.htm.gz","type":"file","size":8610},{"name":"version-info.json","type":"file","size":58},{"name":"videolab.htm.gz","type":"file","size":10758}]''';

/// /json/cfg (trimmed): no timers, boot preset 102, NTP on, no location.
const cfgV16 = r'''{"rev":[1,0],"vid":2606300,"id":{"mdns":"wled-a39308","name":"Matrix","inv":"Light","sui":false},"def":{"ps":102,"on":true,"bri":128},"if":{"live":{"en":true,"mso":false,"rlm":true,"port":5568,"mc":false,"timeout":25,"maxbri":false,"no-gc":true,"offset":0},"ntp":{"en":true,"host":"pool.ntp.org","tz":14,"offset":0,"ampm":false,"ln":0,"lt":0}},"timers":{"cntdwn":{"goal":[20,1,1,0,0,0],"macro":0},"ins":[]}}''';

/// Preset 201 as stored by the device after POST /json/state
/// {"psave":201,"n":"glyph_test_list","playlist":{"ps":[200,102],"dur":[50,70],
/// "transition":[0,5],"repeat":2,"r":false,"end":255},"on":true,"o":true}
/// (end became 0 because no preset was active).
const storedPlaylistV16 = r'''{"playlist":{"ps":[200,102],"dur":[50,70],"transition":[0,5],"repeat":2,"end":0,"r":0},"on":true,"n":"glyph_test_list"}''';

/// /json/cfg timers.ins read back after saving three timers (disabled 03:07
/// Mon/Wed/Fri, sunset −30 min 2 Nov–20 Feb, every hour at :15).
const timersBackV16 = r'''[{"en":0,"hour":3,"min":7,"macro":200,"dow":21,"start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},{"en":0,"hour":254,"min":-30,"macro":201,"dow":127,"start":{"mon":11,"day":2},"end":{"mon":2,"day":20}},{"en":0,"hour":24,"min":15,"macro":200,"dow":127,"start":{"mon":1,"day":1},"end":{"mon":12,"day":31}}]''';
