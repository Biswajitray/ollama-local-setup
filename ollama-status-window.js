ObjC.import('AppKit');
var lines = ["OLLAMA RUNNING","","Model : gemma4-code","Local : http://127.0.0.1:11434","LAN   : http://192.168.178.218:11434","mDNS  : http://Biswajits-Mac-mini.local:11434  (stable name, survives IP changes)","other computers: export OLLAMA_HOST=192.168.178.218:11434","","No close button: this window stays on top while the model is loaded.","It closes by itself when Ollama stops or unloads the model."];
var W = 620, H = 46 + lines.length * 20;
var app = $.NSApplication.sharedApplication;
app.setActivationPolicy(0);                        // NSApplicationActivationPolicyRegular
var win = $.NSWindow.new;
win.setStyleMask(5);                               // Titled(1)|Miniaturizable(4) -- Closable(2) omitted => no close button
win.setContentSize($.NSMakeSize(W, H));
var sf = $.NSScreen.mainScreen.frame.size;         // center on screen
win.setFrameOrigin($.NSMakePoint((sf.width - W) / 2, (sf.height - H) / 2));
win.setTitle("Ollama Status");
win.setLevel(3);                                   // NSFloatingWindowLevel => always on top
win.setReleasedWhenClosed(false);
win.setHidesOnDeactivate(false);
lines.forEach(function (l, i) {
  var f = $.NSTextField.alloc.initWithFrame($.NSMakeRect(16, H - 32 - i * 20, W - 32, 18));
  f.setEditable(false); f.setBordered(false); f.setDrawsBackground(false); f.setSelectable(true);
  f.setStringValue(l);
  f.setFont($.NSFont.systemFontOfSize(13));
  win.contentView.addSubview(f);
});
win.makeKeyAndOrderFront(null);
app.activateIgnoringOtherApps(true);
app.run();
