#!/usr/bin/env python3
"""End-to-end checks of the built app, driven through its test harness.

Launches a separate test copy of Queen Bee (`--testing`, its own support folder, so a copy
you have open is left alone), opens a scratch project with one flow per scenario, runs real
Claude Code sessions on Haiku, and checks what the app did.

    ./scripts/build.sh && ./scripts/e2e.py            # every scenario
    ./scripts/e2e.py guard loop                        # some of them

Scenarios: guard, scroll, fanout, switch, loop, exit, apifail, noclaude.
"""
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build/Build/Products/Debug/QueenBee.app")
# Unix socket paths are capped at 104 bytes, so the test copy's support folder has to be short.
SUPPORT = os.path.expanduser("~/Library/Application Support/QueenBeeTest")

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("  PASS  " if ok else "  FAIL  ") + name + (f"  ({detail})" if detail and not ok else ""), flush=True)
    return ok


# ---- talking to the app ----

def call(support, flow_id, payload, timeout=320):
    body = json.dumps({"kind": "test", "session": f"{flow_id}/test", "payload": payload}).encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(os.path.join(support, "qb.sock"))
        s.sendall(struct.pack(">I", len(body)) + body)
        need = struct.unpack(">I", read_exactly(s, 4))[0]
        return json.loads(read_exactly(s, need))


def read_exactly(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("the app closed the connection")
        buf += chunk
    return buf


class App:
    def __init__(self, project, support=SUPPORT, env=None):
        self.support = support
        shutil.rmtree(support, ignore_errors=True)
        before = set(pids())
        cmd = ["open", "-g", "-n", APP, "--env", f"QB_SUPPORT_DIR={support}"]
        for k, v in (env or {}).items():
            cmd += ["--env", f"{k}={v}"]
        # The defaults-style flag goes first: after a bare flag, macOS would read it as that flag's value.
        cmd += ["--args", "-ApplePersistenceIgnoreState", "YES", "--testing", "--open", project]
        subprocess.run(cmd, check=True)
        deadline = time.time() + 30
        self.pid = None
        while time.time() < deadline:
            new = set(pids()) - before
            if new and os.path.exists(os.path.join(support, "qb.sock")):
                self.pid = new.pop()
                break
            time.sleep(0.3)
        if self.pid is None:
            raise RuntimeError("the test copy of the app didn't start")

    def op(self, flow_id, op, **kw):
        return call(self.support, flow_id, dict(op=op, **kw))

    def state(self, flow_id):
        return self.op(flow_id, "state")

    def wait(self, flow_id, cond, timeout, what):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            last = self.state(flow_id)
            if cond(last):
                return last
            time.sleep(1)
        raise TimeoutError(f"timed out after {timeout}s waiting for {what}; log tail: {last and last.get('log', [])[-6:]}; "
                           f"sessions: { {k: v['state'] for k, v in (last or {}).get('sessions', {}).items()} }")

    def open_flow(self, flow, timeout=150):
        """Puts a flow on screen and waits until every agent's session is ready for input."""
        fid = flow["id"]
        # The socket opens before the project window has loaded its flows, so ask until the flow is known.
        deadline = time.time() + 30
        while "sessions" not in self.state(fid):
            if time.time() > deadline:
                raise RuntimeError(f"the app never loaded the flow {flow['name']}")
            time.sleep(0.5)
        self.op(fid, "select")
        agents = [c["name"] for c in flow["cards"] if c["kind"] == "agent"]
        return self.wait(fid, lambda s: all(s["sessions"].get(a, {}).get("state") == "idle" for a in agents),
                         timeout, f"sessions of {flow['name']} to be idle")

    def quit(self):
        if self.pid:
            subprocess.run(["kill", "-TERM", str(self.pid)])
            for _ in range(40):
                if self.pid not in pids():
                    break
                time.sleep(0.25)


def pids():
    out = subprocess.run(["pgrep", "-x", "QueenBee"], capture_output=True, text=True).stdout.split()
    return [int(p) for p in out]


# ---- building flows ----

def card(kind, name, x, y, **settings):
    width, height = (480, 300) if kind == "agent" else (240, 120)
    c = {"id": name.lower().replace(" ", "").replace("?", "")[:8] + f"{abs(hash(name)) % 9000 + 1000}", "kind": kind, "name": name,
         "x": x, "y": y, "width": width, "height": height}
    if kind == "agent":
        settings.setdefault("model", "haiku")
    c.update(settings)
    return c


def flow(name, cards, links):
    ids = {c["name"]: c["id"] for c in cards}
    fid = "t" + name.lower()[:7].ljust(7, "0")
    return {"version": 1, "id": fid, "name": name, "notifyOrchestrator": False, "cards": cards,
            "links": [{"id": f"l{i}", "from": ids[a], "port": port, "to": ids[b], "maxPasses": passes}
                      for i, (a, port, b, passes) in enumerate(links)]}


def write(project, order, f):
    folder = os.path.join(project, ".queenbee", "flows")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{order}-{f['name'].lower()}.json"), "w") as out:
        json.dump(f, out, indent=2)


SAY = "Whatever you are asked, reply with exactly this and nothing else: "

GUARD = flow("Guard", [
    card("agent", "Alice", 60, 60, instructions="You follow the person's requests exactly."),
    card("agent", "Bob", 600, 60, instructions="When another session messages you, reply with exactly: BOB-GOT-IT"),
    card("agent", "Carol", 1140, 60, instructions="When another session messages you, reply with exactly: CAROL-GOT-IT"),
], [("Alice", "out", "Bob", 3)])

WORDS = ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL"]
FANOUT = flow("Fanout",
              [card("start", "Start", 40, 40, command="Reply with your assigned word.")]
              + [card("agent", f"W{i + 1}", 340 + (i % 4) * 500, 40 + (i // 4) * 320, instructions=SAY + w) for i, w in enumerate(WORDS)]
              + [card("and", "Everyone", 340, 720), card("or", "Fastest", 340, 880),
                 card("end", "All", 660, 720), card("end", "First", 660, 880)],
              [("Start", "out", f"W{i + 1}", 3) for i in range(8)]
              + [(f"W{i + 1}", "out", "Everyone", 3) for i in range(8)]
              + [(f"W{i + 1}", "out", "Fastest", 3) for i in range(8)]
              + [("Everyone", "out", "All", 3), ("Fastest", "out", "First", 3)])

SWITCH = flow("Switch", [
    card("start", "Start", 40, 40, command="The login button crashes the app when I tap it twice."),
    card("switch", "Triage", 340, 40, branches=["bug", "feature"], height=160),
    card("agent", "BugFixer", 660, 40, instructions=SAY + "BUG-HANDLED"),
    card("agent", "Planner", 660, 380, instructions=SAY + "FEATURE-HANDLED"),
    card("end", "Out", 1220, 40),
], [("Start", "out", "Triage", 3), ("Triage", "bug", "BugFixer", 3), ("Triage", "feature", "Planner", 3),
    ("Triage", "other", "Out", 3), ("BugFixer", "out", "Out", 3), ("Planner", "out", "Out", 3)])

LOOP = flow("Loop", [
    card("start", "Start", 40, 40, command="Go"),
    card("agent", "Counter", 340, 40, instructions=(
        "You are a counter. Each message you get has a first line in square brackets, which you ignore. "
        "If the rest of the message is the word Go, reply with exactly: X. "
        "Otherwise the rest is a row of X characters: reply with that row plus one more X. Reply with nothing else.")),
    card("loop", "Enough?", 900, 40, check="contains", value="XXX", maxTries=5, height=140),
    card("end", "Out", 1220, 40),
], [("Start", "out", "Counter", 3), ("Counter", "out", "Enough?", 6), ("Enough?", "again", "Counter", 6), ("Enough?", "done", "Out", 3)])

EXIT = flow("Exit", [
    card("start", "Start", 40, 40, command="Run the shell command `sleep 45`, then reply with exactly: done"),
    card("agent", "Sleeper", 340, 40),
    card("end", "Out", 900, 40),
], [("Start", "out", "Sleeper", 3), ("Sleeper", "out", "Out", 3)])

APIFAIL = flow("Apifail", [
    card("start", "Start", 40, 40, command="Say hi"),
    card("agent", "Broken", 340, 40, model="claude-no-such-model-0"),
    card("end", "Out", 900, 40),
], [("Start", "out", "Broken", 3), ("Broken", "out", "Out", 3)])

FLOWS = {"guard": GUARD, "fanout": FANOUT, "switch": SWITCH, "loop": LOOP, "exit": EXIT, "apifail": APIFAIL}


# ---- scenarios ----

def scenario_guard(app):
    print("guard: an agent may message a linked agent, not an unlinked one", flush=True)
    fid = GUARD["id"]
    app.open_flow(GUARD)
    app.op(fid, "type", card="Alice", text="Use your SendMessage tool to send the message ping to the session named Carol. "
                                           "Then tell me exactly what the tool returned, quoting it word for word.")
    s = app.wait(fid, lambda s: s["sessions"]["Alice"]["lastReply"] and s["sessions"]["Alice"]["state"] == "idle", 120, "Alice to answer")
    reply = s["sessions"]["Alice"]["lastReply"]
    check("the send to unlinked Carol was refused with the canvas's reason", "linked" in reply.lower(), reply[:300])
    time.sleep(4)
    s = app.state(fid)
    check("Carol received nothing", s["sessions"]["Carol"]["lastReply"] is None and s["sessions"]["Carol"]["state"] == "idle",
          str(s["sessions"]["Carol"]))
    app.op(fid, "type", card="Alice", text="Now send the message ping to the session named Bob the same way, and tell me what the tool returned.")
    try:
        s = app.wait(fid, lambda s: s["sessions"]["Alice"]["lastReply"] not in (None, reply) and s["sessions"]["Alice"]["state"] == "idle",
                     120, "Alice to answer the second request")
        second = s["sessions"]["Alice"]["lastReply"]
        try:
            s = app.wait(fid, lambda s: s["sessions"]["Bob"]["lastReply"], 60, "Bob to get Alice's message")
            check("the send to linked Bob went through", "BOB-GOT-IT" in s["sessions"]["Bob"]["lastReply"], s["sessions"]["Bob"]["lastReply"][:200])
        except TimeoutError:
            check("the send to linked Bob went through", False, "Bob never answered. Alice said: " + second[:500])
    except TimeoutError as e:
        check("the send to linked Bob went through", False, str(e)[:300])
    app.wait(fid, lambda s: s["orchestrator"]["state"] == "idle", 90, "the orchestrator to be ready")
    app.op(fid, "type", card="orchestrator", text="Use your SendMessage tool to send the message ping to the agent named Carol. Then tell me what the tool returned.")
    try:
        s = app.wait(fid, lambda s: s["sessions"]["Carol"]["lastReply"], 120, "Carol to get the orchestrator's message")
        check("the orchestrator can message any agent by its card name", "CAROL-GOT-IT" in s["sessions"]["Carol"]["lastReply"],
              s["sessions"]["Carol"]["lastReply"][:200])
    except TimeoutError:
        said = app.state(fid)["orchestrator"]["lastReply"] or ""
        check("the orchestrator can message any agent by its card name", False, "Carol never answered. The orchestrator said: " + said[:500])


def scenario_scroll(app):
    print("scroll: wheel events pan the canvas unless a terminal has the keyboard", flush=True)
    fid = GUARD["id"]
    app.open_flow(GUARD)
    app.op(fid, "zoom", to=1.0)
    app.op(fid, "focus")
    time.sleep(0.5)

    def y():
        return app.state(fid)["canvas"]["y"]

    # A real event handed to the app is the fuller test. A window behind others may not get it,
    # and then the same events are given straight to the canvas's own scroll handling.
    y0 = y()
    app.op(fid, "scroll", dy=-160, mode="system")
    time.sleep(0.8)
    mode = "system" if abs(y() - y0) > 20 else "direct"
    print(f"        scroll events delivered by: {mode}", flush=True)
    if mode == "direct":
        app.op(fid, "scroll", dy=-160, mode=mode)
        time.sleep(0.6)
    y1 = y()
    check("scrolling over bare canvas pans it", abs(y1 - y0) > 20, f"y {y0} -> {y1}")
    app.op(fid, "scroll", card="Alice", dy=-160, mode=mode)
    time.sleep(0.6)
    y2 = y()
    check("scrolling over a terminal that isn't focused pans the canvas", abs(y2 - y1) > 20, f"y {y1} -> {y2}")
    app.op(fid, "scroll", dy=400, mode=mode)
    time.sleep(0.6)
    y3 = y()
    app.op(fid, "focus", card="Alice")
    time.sleep(0.6)
    s = app.state(fid)
    check("clicking into a terminal marks its card as focused", s["focusedCard"] == "Alice", str(s["focusedCard"]))
    app.op(fid, "scroll", card="Alice", dy=-160, mode=mode)
    time.sleep(0.6)
    y4 = y()
    check("scrolling over the focused terminal leaves the canvas where it is", abs(y4 - y3) < 1, f"y {y3} -> {y4}")
    app.op(fid, "focus")
    time.sleep(0.4)
    check("clicking empty canvas takes focus back", app.state(fid)["focusedCard"] is None)
    m0 = app.state(fid)["canvas"]["magnification"]
    app.op(fid, "zoom", to=0.5)
    time.sleep(0.3)
    m1 = app.state(fid)["canvas"]["magnification"]
    check("zoom changes the canvas's magnification", abs(m0 - 1.0) < 0.01 and abs(m1 - 0.5) < 0.01, f"{m0} -> {m1}")


def scenario_fanout(app):
    print("fanout: eight agents at once, And waits for all, Or takes the first", flush=True)
    fid = FANOUT["id"]
    started = time.time()
    app.open_flow(FANOUT, timeout=240)
    check("nine sessions (eight agents and the orchestrator) all came up", True, f"{time.time() - started:.0f}s")
    print(f"        sessions ready in {time.time() - started:.0f}s", flush=True)
    app.op(fid, "run")
    s = app.wait(fid, lambda s: not s["isRunning"] and "All" in s["results"], 240, "the fan-out run to finish")
    everything = s["results"].get("All", "")
    check("And passed on all eight answers together", all(w in everything for w in WORDS), everything[:300])
    first = s["results"].get("First", "")
    check("Or passed on exactly one answer", sum(w in first for w in WORDS) == 1, first[:200])
    dropped = sum("dropped a later reply" in line for line in s["log"])
    check("Or dropped the seven later answers", dropped == 7, f"dropped {dropped}")
    check("the run ended on its own", not s["isRunning"])
    marks = s["marks"]
    check("the And card shows one pass and nothing held", marks.get("Everyone", {}).get("passes") == 1 and marks["Everyone"]["holding"] == 0,
          str(marks.get("Everyone")))
    check("the Or card shows one passed on and seven dropped", marks.get("Fastest", {}).get("passes") == 1 and marks["Fastest"]["holding"] == 7,
          str(marks.get("Fastest")))
    check("every worker shows one reply", all(marks.get(f"W{i + 1}", {}).get("passes") == 1 for i in range(8)))
    check("no link is still marked live after the run", s["liveLinks"] == 0, str(s["liveLinks"]))


def scenario_switch(app):
    print("switch: Claude picks the branch a message belongs to", flush=True)
    fid = SWITCH["id"]
    app.open_flow(SWITCH)
    app.op(fid, "run")
    s = app.wait(fid, lambda s: not s["isRunning"] and "Out" in s["results"], 180, "the bug run to finish")
    check("a crash report went out the bug branch", any('Switch "Triage" → bug' in line for line in s["log"]), str(s["log"][-5:]))
    check("the bug agent's answer reached End", "BUG-HANDLED" in s["results"]["Out"], s["results"]["Out"][:200])
    check("the other branch's agent was left alone", s["sessions"]["Planner"]["lastReply"] is None)
    check("the Switch card shows the branch it took", s["marks"].get("Triage", {}).get("lastPort") == "bug", str(s["marks"].get("Triage")))
    check("the untaken branch's agent has no run mark", "Planner" not in s["marks"], str(s["marks"].get("Planner")))
    before = len(s["log"])
    app.op(fid, "run", command="Please add a dark mode option to the settings screen.")
    s = app.wait(fid, lambda s: not s["isRunning"] and "FEATURE" in s["results"].get("Out", ""), 180, "the feature run to finish")
    check("a feature request went out the feature branch", any('Switch "Triage" → feature' in line for line in s["log"][before:]), str(s["log"][before:]))


def scenario_loop(app):
    print("loop: goes round until its condition holds", flush=True)
    fid = LOOP["id"]
    app.open_flow(LOOP)
    app.op(fid, "run")
    s = app.wait(fid, lambda s: not s["isRunning"] and "Out" in s["results"], 240, "the loop run to finish")
    log = s["log"]
    check("the loop sent the agent round twice", sum("→ Again" in line for line in log) == 2, str([l for l in log if "Loop" in l]))
    check("the loop left by Done once the condition held", any('Loop "Enough?" → Done' == line for line in log), str([l for l in log if "Loop" in l]))
    check("the final answer is the third reply", s["results"]["Out"].strip().endswith("XXX") and "XXXX" not in s["results"]["Out"], s["results"]["Out"][:100])
    marks = s["marks"]
    check("the agent's card counts three replies", marks.get("Counter", {}).get("passes") == 3, str(marks.get("Counter")))
    check("the Loop card counts each output", marks.get("Enough?", {}).get("ports") == {"again": 2, "done": 1}
          and marks["Enough?"]["lastPort"] == "done", str(marks.get("Enough?")))
    check("the End card counts one arrival", marks.get("Out", {}).get("arrivals") == 1, str(marks.get("Out")))
    check("link pass counts match the route taken", sorted(s["linkPasses"]) == [1, 1, 2, 3], str(s["linkPasses"]))


def scenario_exit(app):
    print("exit: a session dying mid-run stops the run and says why", flush=True)
    fid = EXIT["id"]
    app.open_flow(EXIT)
    app.op(fid, "run")
    app.wait(fid, lambda s: s["sessions"]["Sleeper"]["state"] in ("working", "needsYou"), 60, "Sleeper to start working")
    time.sleep(4)
    app.op(fid, "kill", card="Sleeper")
    try:
        s = app.wait(fid, lambda s: not s["isRunning"], 30, "the run to stop after the session died")
    except TimeoutError as e:
        check("the run stopped when the session died", False, str(e)[:300])
        return
    check("the run stopped when the session died", True)
    check("the log says which agent failed", any("Sleeper failed" in line for line in s["log"]), str(s["log"][-4:]))
    check("the card shows the session as exited", s["sessions"]["Sleeper"]["state"] == "exited", s["sessions"]["Sleeper"]["state"])
    check("the card where the run stopped is marked failed", s["marks"].get("Sleeper", {}).get("failed") is True and s["activity"] == "failed",
          f"{s['marks'].get('Sleeper')} {s['activity']}")
    app.op(fid, "restart", card="Sleeper")
    try:
        app.wait(fid, lambda s: s["sessions"]["Sleeper"]["state"] == "idle", 90, "Sleeper to come back")
        check("Restart brings the session back", True)
    except TimeoutError as e:
        check("Restart brings the session back", False, str(e)[:300])


def scenario_apifail(app):
    print("apifail: a turn that ends in an API error stops the run", flush=True)
    fid = APIFAIL["id"]
    app.wait(fid, lambda s: "sessions" in s, 30, "the flow to load")
    app.op(fid, "select")
    s = app.wait(fid, lambda s: s["sessions"]["Broken"]["state"] in ("idle", "exited", "failed"), 90, "Broken's session to settle")
    print(f"        a session with an unknown model starts as: {s['sessions']['Broken']['state']}", flush=True)
    app.op(fid, "run")
    try:
        s = app.wait(fid, lambda s: not s["isRunning"] and any("failed" in line for line in s["log"]), 120, "the run to stop")
    except TimeoutError as e:
        check("the run stopped when the turn failed", False, str(e)[:400])
        return
    check("the run stopped when the turn failed", True)
    check("the log says which agent failed and why", any("Broken failed" in line for line in s["log"]), str(s["log"][-4:]))
    print(f"        card state afterwards: {s['sessions']['Broken']['state']}; log: {s['log'][-2:]}", flush=True)
    check("the card shows failed or exited", s["sessions"]["Broken"]["state"] in ("failed", "exited"), s["sessions"]["Broken"]["state"])


def scenario_noclaude(project):
    print("noclaude: the app says so when Claude Code isn't installed", flush=True)
    empty = tempfile.mkdtemp(prefix="qb-nohome-")
    support = SUPPORT + "NoClaude"
    app = App(project, support=support, env={"HOME": empty, "CFFIXED_USER_HOME": empty, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"})
    try:
        deadline = time.time() + 40
        s = {}
        while time.time() < deadline:
            s = call(support, "*", {"op": "app"})
            if s.get("environmentReady"):
                break
            time.sleep(0.5)
        check("the app finished looking for claude", s.get("environmentReady") is True, str(s))
        check("it reports that Claude Code isn't installed", "isn't installed" in (s.get("problem") or ""), str(s))
    finally:
        app.quit()
        shutil.rmtree(support, ignore_errors=True)


def main():
    wanted = sys.argv[1:] or ["guard", "scroll", "fanout", "switch", "loop", "exit", "apifail", "noclaude"]
    if not os.path.exists(APP):
        sys.exit("Build the app first: ./scripts/build.sh")
    project = tempfile.mkdtemp(prefix="qb-e2e-")
    # Guard is written first so it is the flow the app opens on, and the others wait their turn.
    for i, name in enumerate(["guard", "fanout", "switch", "loop", "exit", "apifail"]):
        write(project, i, FLOWS[name])
    print(f"project: {project}", flush=True)

    in_app = [w for w in wanted if w != "noclaude"]
    if in_app:
        app = App(project)
        try:
            for name in in_app:
                try:
                    globals()[f"scenario_{name}"](app)
                except Exception as e:  # one scenario failing shouldn't hide the others
                    check(f"{name} ran to the end", False, f"{type(e).__name__}: {e}"[:500])
                flow_id = (GUARD if name == "scroll" else FLOWS[name])["id"]
                # Keep Guard's sessions for the scroll scenario that follows it.
                if not (name == "guard" and "scroll" in in_app):
                    app.op(flow_id, "close")
        finally:
            app.quit()
            shutil.rmtree(SUPPORT, ignore_errors=True)
    if "noclaude" in wanted:
        try:
            scenario_noclaude(project)
        except Exception as e:
            check("noclaude ran to the end", False, f"{type(e).__name__}: {e}"[:500])

    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
    for name, _, detail in failed:
        print(f"  FAIL {name}: {detail}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
