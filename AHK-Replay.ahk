#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"

; ================= 配置 =================
INTER_LOOP_MS := 3000       ; 每轮回放之间的固定间隔(毫秒)
MAX_WAIT_COMPRESS := 2500   ; 录制时超过此长度的停顿压缩到该值(毫秒)，保留页面过渡时间
RECORD_DIR := A_ScriptDir "\recordings"
; ========================================

; ================= 快捷键 =================
; F2  开始/结束录制（结束自动保存并询问回放次数）
; F4  回放最近一次录制
; F5  从 recordings 文件夹挑选一个录制回放
; F12 急停/退出（回放中按了立即停止）
; 录制内容：鼠标点击、滚轮、Ctrl+V（含当时的剪贴板内容）、Ctrl+A、Esc、Enter
; ==========================================

global events := [], recording := false, startTick := 0, lastName := ""

DirCreate RECORD_DIR

; ---------- 日志 ----------
LogEvent(msg) {
    try FileAppend A_Hour ":" A_Min ":" A_Sec " " msg "`n", A_ScriptDir "\ahk-replay.log"
}

; ---------- 剪贴板内容转义（行式文件存储：仅转义 反斜杠 与 换行） ----------
ClipEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    return s
}

; 单遍扫描解码（避免 \\n 被二次误解析为换行）
ClipUnescape(s) {
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = "\") {
            nxt := SubStr(s, i + 1, 1)
            switch nxt {
                case "n": out .= "`n", i += 2
                case "r": out .= "`r", i += 2
                case "\": out .= "\", i += 2
                default:  out .= c, i += 1
            }
        } else {
            out .= c
            i += 1
        }
    }
    return out
}

; ---------- 录制 ----------
ToggleRecord() {
    global events, recording, startTick
    if !recording {
        events := []
        recording := true
        startTick := A_TickCount
        ToolTip "● 录制中… 完成操作后按 F2（点击/滚轮/Ctrl+V/Ctrl+A/Esc/Enter 都会记录）"
        LogEvent("REC_ON")
    } else {
        recording := false
        if (events.Length = 0) {
            ToolTip "本次没有录到任何动作"
            SetTimer () => ToolTip(), -1500
            LogEvent("REC_OFF 空")
            return
        }
        ib := InputBox("给这段录制起个名字：", "保存录制", "w300 h130",
            "rec-" . FormatTime(, "MMdd-HHmmss"))
        if (ib.Result != "OK")
            return
        name := Trim(ib.Value)
        if (name = "")
            name := "rec-" . FormatTime(, "MMdd-HHmmss")
        SaveRecording(name)
        ToolTip "已保存：recordings\" name ".ahkr（" events.Length " 个动作）"
        SetTimer () => ToolTip(), -1800
        LogEvent("REC_OFF name=" name " len=" events.Length)
        AskCountAndReplay(events)
    }
}

OnClick() {
    global events, recording, startTick
    if recording {
        MouseGetPos &x, &y
        events.Push({t: A_TickCount - startTick, k: "click", x: x, y: y, clip: ""})
    }
}

OnWheel(kind) {
    global events, recording, startTick
    if recording {
        MouseGetPos &x, &y
        events.Push({t: A_TickCount - startTick, k: kind, x: x, y: y, clip: ""})
    }
}

OnKey(kind) {
    global events, recording, startTick
    if recording
        events.Push({t: A_TickCount - startTick, k: kind, x: 0, y: 0, clip: ""})
}

; 粘贴事件：把当时的剪贴板内容一起记录（回放时还原）
OnPaste() {
    global events, recording, startTick
    if recording
        events.Push({t: A_TickCount - startTick, k: "v", x: 0, y: 0, clip: A_Clipboard})
}

; ---------- 存取 ----------
SaveRecording(name) {
    global events, RECORD_DIR
    s := ""
    for ev in events
        s .= ev.t "|" ev.k "|" ev.x "|" ev.y "|" ClipEscape(ev.clip) "`n"
    file := RECORD_DIR "\" name ".ahkr"
    if FileExist(file)
        FileDelete file
    FileAppend s, file, "UTF-8"
    LogEvent("SAVED " name " len=" events.Length)
}

LoadRecordingFile(file) {
    evs := []
    txt := FileRead(file, "UTF-8")
    for line in StrSplit(txt, "`n", "`r") {
        line := Trim(line, Chr(0xFEFF) " `t")
        if (line = "")
            continue
        p := StrSplit(line, "|", , 5)
        if (p.Length < 4)
            continue
        clip := (p.Length >= 5) ? ClipUnescape(p[5]) : ""
        evs.Push({t: Integer(p[1]), k: p[2], x: Integer(p[3]), y: Integer(p[4]), clip: clip})
    }
    return evs
}

LatestRecording() {
    global RECORD_DIR
    best := "", bestTime := 0
    Loop Files RECORD_DIR "\*.ahkr" {
        t := A_LoopFileTimeModified
        if (t > bestTime) {
            bestTime := t
            best := A_LoopFileFullPath
        }
    }
    return best
}

; ---------- 回放 ----------
AskCountAndReplay(evs) {
    ib := InputBox("回放多少次？（回放中按 F12 急停）", "循环回放", "w300 h140", "1")
    if (ib.Result != "OK")
        return
    if !(ib.Value ~= '^\d+$') {
        MsgBox "请输入数字"
        return
    }
    Replay(Integer(ib.Value), evs)
}

Replay(n, evs) {
    global INTER_LOOP_MS, MAX_WAIT_COMPRESS
    if (evs.Length = 0) {
        ToolTip "没有可回放的动作"
        SetTimer () => ToolTip(), -1500
        return
    }
    ToolTip "3 秒后开始回放… 请切到目标窗口"
    Sleep 3000
    LogEvent("REPLAY n=" n " evs=" evs.Length)

    Loop n {
        prev := 0
        for ev in evs {
            wait := ev.t - prev
            prev := ev.t
            if (wait > MAX_WAIT_COMPRESS)
                wait := MAX_WAIT_COMPRESS
            if (wait > 0)
                Sleep wait
            switch ev.k {
                case "click":  Click ev.x, ev.y
                case "v":
                    if (ev.clip != "") {
                        A_Clipboard := ev.clip
                        Sleep 200
                    }
                    Send "^v"
                case "a":      Send "^a"
                case "esc":    Send "{Esc}"
                case "enter":  Send "{Enter}"
                case "wu":     MouseMove ev.x, ev.y, 2
                               Send "{WheelUp}"
                case "wd":     MouseMove ev.x, ev.y, 2
                               Send "{WheelDown}"
            }
        }
        ToolTip "回放完成 " A_Index "/" n "  (F12 停止)"
        if (A_Index < n)
            Sleep INTER_LOOP_MS
    }
    ToolTip "全部回放完成 ✓"
    SetTimer () => ToolTip(), -2000
    LogEvent("REPLAY_DONE n=" n)
}

ReplayLast() {
    global lastName
    file := lastName = "" ? LatestRecording() : RECORD_DIR "\" lastName ".ahkr"
    if (file = "" || !FileExist(file)) {
        file := LatestRecording()
    }
    if (file = "" || !FileExist(file)) {
        ToolTip "还没有录制文件，先按 F2 录一次"
        SetTimer () => ToolTip(), -2000
        return
    }
    evs := LoadRecordingFile(file)
    AskCountAndReplay(evs)
}

PickAndReplay() {
    global RECORD_DIR
    file := FileSelectFile(1, RECORD_DIR, "选择录制文件", "录制文件 (*.ahkr)")
    if (file = "")
        return
    evs := LoadRecordingFile(file)
    AskCountAndReplay(evs)
}

; ---------- 快捷键 ----------
F2:: ToggleRecord()
F4:: ReplayLast()
F5:: PickAndReplay()
F12:: ExitApp
~LButton:: OnClick()
~^v:: OnPaste()
~^a:: OnKey("a")
~Esc:: OnKey("esc")
~Enter:: OnKey("enter")
~WheelUp:: OnWheel("wu")
~WheelDown:: OnWheel("wd")

; ---------- 启动提示 ----------
ToolTip "已就绪：F2 录制 | F4 回放最近 | F5 选择录制文件 | F12 退出"
LogEvent("LAUNCH")
SetTimer () => ToolTip(), -3500
