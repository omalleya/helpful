/**
 * Kanban board view of tmux sessions, launched in a tmux popup by `prefix + b`.
 *
 * Sessions are cards in stage columns (unclassified → in-progress →
 * self-review → in-review → merged, plus an experimental parking lot). A
 * session's stage is derived from its worktree's GitHub PR and overridable by
 * hand — but none of those rules live here: this is a renderer over
 * `session-switcher.sh --json`, so the board and the `prefix + s` list agree on
 * stage by construction.
 *
 * Actions the wrapper shell has to perform (it owns the tty, this does not) are
 * written to $BOARD_ACTION_FILE before exit; see session-board.sh.
 */
import { execFile } from "node:child_process";
import { writeFileSync } from "node:fs";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Box, type Key, render, Text, useApp, useInput, useStdout } from "ink";

/** Path to session-switcher.sh, the single source of truth for board data. */
const SWITCHER = process.env["SESSION_SWITCHER"] ?? "";
/** Where to leave a follow-up action for the wrapper shell. */
const ACTION_FILE = process.env["BOARD_ACTION_FILE"] ?? "";

/** How often to re-read session state and kick a background PR warm. */
const REFRESH_MS = 2000;
/** Narrowest a column may get before the board scrolls columns instead. */
const COL_MIN_WIDTH = 24;
/** Rows one card occupies: a 2-row border around 3 content lines. */
const CARD_ROWS = 5;
/** Seconds a status message stays on screen. */
const STATUS_MS = 4000;

/** One session, exactly as `session-switcher.sh --json` emits it. */
type Session = {
  name: string;
  display: string;
  stage: string;
  override: string;
  windows: number;
  attached: boolean;
  claude: string;
  codex: string;
  path: string;
  branch: string;
  ticket: string;
  pr: {
    state: string;
    isDraft: boolean;
    number: string;
    url: string;
    title: string;
  };
};

function Board({ stages }: { stages: string[] }) {
  const { exit } = useApp();
  const { stdout } = useStdout();

  const [sessions, setSessions] = useState<Session[]>([]);
  const [col, setCol] = useState(0);
  const [row, setRow] = useState(0);
  const [winStart, setWinStart] = useState(0);
  const [query, setQuery] = useState("");
  const [searching, setSearching] = useState(false);
  const [preview, setPreview] = useState(false);
  const [previewText, setPreviewText] = useState("");
  const [status, setStatus] = useState("");
  const [size, setSize] = useState({
    cols: stdout.columns ?? 120,
    rows: stdout.rows ?? 30,
  });

  /**
   * Name of the card the cursor is on, so a refresh that moves a session
   * between columns (a PR going from draft to open, say) carries the cursor
   * with it rather than leaving it on whatever slid into that slot.
   */
  const anchor = useRef<string | null>(null);

  const load = useCallback(() => {
    execFile(
      SWITCHER,
      ["--json"],
      { maxBuffer: 16 * 1024 * 1024 },
      (error, stdoutText) => {
        if (error) {
          setStatus(`could not read sessions: ${error.message}`);
          return;
        }
        try {
          setSessions(JSON.parse(stdoutText) as Session[]);
        } catch {
          setStatus("could not parse session data");
        }
      },
    );
  }, []);

  useEffect(() => {
    load();
    const timer = setInterval(() => {
      load();
      execFile(SWITCHER, ["--warm-prs"], () => {});
    }, REFRESH_MS);
    return () => clearInterval(timer);
  }, [load]);

  useEffect(() => {
    const onResize = () =>
      setSize({ cols: stdout.columns ?? 120, rows: stdout.rows ?? 30 });
    stdout.on("resize", onResize);
    return () => {
      stdout.off("resize", onResize);
    };
  }, [stdout]);

  useEffect(() => {
    if (!status) return;
    const timer = setTimeout(() => setStatus(""), STATUS_MS);
    return () => clearTimeout(timer);
  }, [status]);

  const columns = useMemo(() => {
    const needle = query.toLowerCase();
    const matches = (session: Session) =>
      needle === "" ||
      [session.name, session.ticket, session.pr.title, session.branch]
        .join(" ")
        .toLowerCase()
        .includes(needle);
    return stages.map((stage) =>
      sessions.filter((session) => session.stage === stage && matches(session)),
    );
  }, [sessions, stages, query]);

  const current = columns[col]?.[row];

  useEffect(() => {
    if (current) anchor.current = current.name;
  }, [current]);

  useEffect(() => {
    const want = anchor.current;
    if (want) {
      for (let index = 0; index < columns.length; index++) {
        const found = columns[index]!.findIndex((s) => s.name === want);
        if (found >= 0) {
          if (index !== col) setCol(index);
          if (found !== row) setRow(found);
          return;
        }
      }
    }
    // The anchored session is gone — killed, or filtered out by a search. Fall
    // back to the nearest card rather than leaving the cursor parked on an empty
    // column, where every key would be a no-op.
    const length = columns[col]?.length ?? 0;
    if (length > 0) {
      if (row >= length) setRow(length - 1);
      return;
    }
    const populated = columns.findIndex((cards) => cards.length > 0);
    if (populated >= 0) {
      setCol(populated);
      setRow(0);
    }
    // Re-anchors on new data and on a filter change, not on cursor moves —
    // those set the anchor via the effect above instead.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessions, query]);

  const visibleCount = Math.min(
    stages.length,
    Math.max(1, Math.floor(size.cols / (COL_MIN_WIDTH + 1))),
  );

  useEffect(() => {
    setWinStart((start) => {
      const maxStart = Math.max(0, stages.length - visibleCount);
      if (col < start) return col;
      if (col >= start + visibleCount) return col - visibleCount + 1;
      return Math.min(start, maxStart);
    });
  }, [col, visibleCount, stages.length]);

  const previewRows = preview ? Math.min(10, Math.max(4, size.rows - 24)) : 0;
  const chromeRows = 3 + (preview ? previewRows + 1 : 0);
  const maxCards = Math.max(
    1,
    Math.floor((size.rows - chromeRows) / CARD_ROWS),
  );
  const colWidth = Math.max(
    COL_MIN_WIDTH,
    Math.floor((size.cols - visibleCount) / visibleCount),
  );

  useEffect(() => {
    if (!preview || !current) {
      setPreviewText("");
      return;
    }
    execFile(
      "tmux",
      ["capture-pane", "-p", "-t", current.name],
      { maxBuffer: 4 * 1024 * 1024 },
      (error, text) => {
        if (error) {
          setPreviewText("");
          return;
        }
        const lines = text.replace(/\s+$/, "").split("\n");
        setPreviewText(lines.slice(-previewRows).join("\n"));
      },
    );
  }, [preview, current, previewRows]);

  const finish = useCallback(
    (action?: string) => {
      if (action && ACTION_FILE) writeFileSync(ACTION_FILE, `${action}\n`);
      exit();
    },
    [exit],
  );

  const switchTo = useCallback(
    (session: Session | undefined) => {
      if (!session) return;
      execFile("tmux", ["switch-client", "-t", session.name], () => finish());
    },
    [finish],
  );

  const moveCard = useCallback(
    (delta: number) => {
      if (!current) return;
      const index = stages.indexOf(current.stage);
      const target =
        stages[Math.min(stages.length - 1, Math.max(0, index + delta))];
      if (!target || target === current.stage) return;
      // A merged PR is terminal in session-switcher.sh, which stays the
      // authority; this only spares the user a card that visibly bounces back.
      if (
        (current.pr.state === "MERGED" || current.pr.state === "CLOSED") &&
        target !== "experimental"
      ) {
        setStatus(
          `#${current.pr.number} is ${current.pr.state.toLowerCase()} — pinned to merged`,
        );
        return;
      }
      anchor.current = current.name;
      setSessions((prev) =>
        prev.map((session) =>
          session.name === current.name
            ? { ...session, stage: target, override: target }
            : session,
        ),
      );
      execFile(
        "tmux",
        ["set-option", "-t", current.name, "@state", target],
        () => load(),
      );
    },
    [current, stages, load],
  );

  const clearOverride = useCallback(() => {
    if (!current) return;
    anchor.current = current.name;
    execFile("tmux", ["set-option", "-t", current.name, "-u", "@state"], () => {
      setStatus(`${current.display}: stage back to derived`);
      load();
    });
  }, [current, load]);

  const openPr = useCallback(() => {
    if (!current) return;
    if (current.pr.url) {
      execFile("open", [current.pr.url], () => {});
      return;
    }
    setStatus(`${current.display}: no PR — opening the branch`);
    execFile(SWITCHER, ["--open-pr", current.name], () => {});
  }, [current]);

  const openLinear = useCallback(() => {
    if (!current) return;
    execFile(SWITCHER, ["--linear-url", current.name], (error, url) => {
      const trimmed = (url ?? "").trim();
      if (error || !trimmed) {
        setStatus(
          current.ticket
            ? "no Linear workspace configured (see README)"
            : "no Linear issue key on this branch",
        );
        return;
      }
      execFile("open", [trimmed], () => {});
    });
  }, [current]);

  /** Step the cursor between columns, clamped to the ends. */
  const moveCol = (delta: number) =>
    setCol((value) => Math.max(0, Math.min(stages.length - 1, value + delta)));

  /** Step the cursor between cards of the current column, clamped to the ends. */
  const moveRow = (delta: number) =>
    setRow((value) =>
      Math.max(0, Math.min((columns[col]?.length ?? 1) - 1, value + delta)),
    );

  /**
   * One hotkey in board (non-search) mode. Split out from useInput because a
   * held key autorepeats faster than stdin is drained, so several presses can
   * arrive as one chunk — see the dispatcher below.
   */
  const handleKey = (input: string, key: Key) => {
    if (key.escape || input === "q" || (key.ctrl && input === "c")) {
      finish();
      return;
    }
    if (key.tab) {
      finish("list");
      return;
    }
    if (key.return) {
      switchTo(current);
      return;
    }
    if (input === "/") {
      setSearching(true);
      return;
    }
    if (input === "H") {
      moveCard(-1);
      return;
    }
    if (input === "L") {
      moveCard(1);
      return;
    }
    if (input === "h" || key.leftArrow) {
      moveCol(-1);
      setRow(0);
      return;
    }
    if (input === "l" || key.rightArrow) {
      moveCol(1);
      setRow(0);
      return;
    }
    if (input === "k" || key.upArrow) {
      moveRow(-1);
      return;
    }
    if (input === "j" || key.downArrow) {
      moveRow(1);
      return;
    }
    if (input === "d") {
      clearOverride();
      return;
    }
    if (input === "o") {
      openPr();
      return;
    }
    if (input === "i") {
      openLinear();
      return;
    }
    if (input === "p") {
      setPreview((value) => !value);
      return;
    }
    if (input === "X" || (key.ctrl && input === "x")) {
      if (current) finish(`clean\t${current.name}`);
      return;
    }
  };

  useInput((input, key) => {
    if (searching) {
      if (key.escape) {
        setSearching(false);
        setQuery("");
        return;
      }
      if (key.return) {
        switchTo(current);
        return;
      }
      if (key.backspace || key.delete) {
        if (query === "") setSearching(false);
        else setQuery((value) => value.slice(0, -1));
        return;
      }
      // Arrows still navigate while filtering, so a hit can be picked without
      // leaving search. Unlike `h`/`l`, they keep the row — the filtered columns
      // are short and losing your place in them is worse than a stale index.
      if (key.leftArrow) moveCol(-1);
      else if (key.rightArrow) moveCol(1);
      else if (key.upArrow) moveRow(-1);
      else if (key.downArrow) moveRow(1);
      // A chunk of several characters is a paste, which belongs in the query
      // verbatim — so search mode wants no per-character splitting.
      else if (input && !key.ctrl && !key.meta)
        setQuery((value) => value + input);
      return;
    }

    // Held keys autorepeat faster than stdin is drained, so `jjj` can arrive as
    // one chunk. Dispatching per character keeps a held j scrolling instead of
    // matching nothing — and, worse, letting the next keypress act on the card
    // the cursor should already have left.
    if (input.length > 1) {
      for (const character of input) handleKey(character, key);
      return;
    }
    handleKey(input, key);
  });

  const total = sessions.length;
  const shown = columns.reduce((sum, cards) => sum + cards.length, 0);

  return (
    <Box flexDirection="column" width={size.cols}>
      <Box>
        <Text bold>{" board "}</Text>
        <Text dimColor>
          {shown === total ? `${total} sessions` : `${shown}/${total} sessions`}
        </Text>
        {winStart > 0 && <Text dimColor>{"  ‹"}</Text>}
        {winStart + visibleCount < stages.length && <Text dimColor>{"›"}</Text>}
        {status !== "" && <Text color="yellow">{`   ${status}`}</Text>}
      </Box>

      <Box>
        {stages
          .slice(winStart, winStart + visibleCount)
          .map((stage, offset) => {
            const index = winStart + offset;
            const cards = columns[index] ?? [];
            const focused = index === col;
            return (
              <Column
                key={stage}
                stage={stage}
                cards={cards}
                width={colWidth}
                focused={focused}
                cursor={focused ? row : -1}
                maxCards={maxCards}
              />
            );
          })}
      </Box>

      {preview && (
        <Box
          flexDirection="column"
          borderStyle="single"
          borderColor="gray"
          height={previewRows + 2}
          width={size.cols}
        >
          <Text dimColor wrap="truncate-end">
            {current ? ` ${current.name}` : " no session"}
          </Text>
          {previewText.split("\n").map((line, index) => (
            <Text key={index} wrap="truncate-end">
              {line}
            </Text>
          ))}
        </Box>
      )}

      <Box>
        {searching ? (
          <Text>
            <Text color="cyan">{"search ▸ "}</Text>
            <Text>{query}</Text>
            <Text dimColor>{"   ↵ switch · ⌫ empty or Esc exits"}</Text>
          </Text>
        ) : (
          <Text dimColor wrap="truncate-end">
            {
              " h/l column  j/k card  H/L move  ↵ switch  [o]github [i]linear  [d]erive  [p]review  [/]search  Tab list  C-x clean  q quit"
            }
          </Text>
        )}
      </Box>
    </Box>
  );
}

/** One stage column: a labelled header over its cards, windowed to fit. */
function Column({
  stage,
  cards,
  width,
  focused,
  cursor,
  maxCards,
}: {
  stage: string;
  cards: Session[];
  width: number;
  focused: boolean;
  cursor: number;
  maxCards: number;
}) {
  const start = Math.max(
    0,
    Math.min(
      cursor >= 0 ? cursor - Math.floor(maxCards / 2) : 0,
      Math.max(0, cards.length - maxCards),
    ),
  );
  const visible = cards.slice(start, start + maxCards);
  const hidden = cards.length - visible.length - start;

  return (
    <Box flexDirection="column" width={width} marginRight={1}>
      <Text
        bold={focused}
        color={focused ? "cyan" : "gray"}
        wrap="truncate-end"
      >
        {`${focused ? "▸ " : "  "}${stage} ${cards.length}`}
      </Text>
      {cards.length === 0 && <Text dimColor>{"   —"}</Text>}
      {start > 0 && <Text dimColor>{`   ↑ ${start} more`}</Text>}
      {visible.map((card, offset) => (
        <Card
          key={card.name}
          session={card}
          selected={start + offset === cursor}
          width={width}
        />
      ))}
      {hidden > 0 && <Text dimColor>{`   ↓ ${hidden} more`}</Text>}
    </Box>
  );
}

/** One session card: name, chips, and the PR title as its summary line. */
function Card({
  session,
  selected,
  width,
}: {
  session: Session;
  selected: boolean;
  width: number;
}) {
  const summary = session.pr.title || session.branch || session.path || "—";
  return (
    <Box
      flexDirection="column"
      width={width}
      borderStyle="round"
      borderColor={selected ? "cyan" : "gray"}
      borderDimColor={!selected}
      paddingX={1}
    >
      <Text
        bold={selected}
        color={selected ? "cyan" : undefined}
        wrap="truncate-end"
      >
        {session.display}
      </Text>
      {/* The window count is unconditional so this line is never empty: Ink
          gives a Text with no content zero height, which would leave cards of
          two different heights and knock the columns out of alignment. */}
      <Text wrap="truncate-end">
        {session.ticket !== "" && <Text dimColor>{session.ticket} </Text>}
        <PrChip pr={session.pr} />
        <Text dimColor>{`  ${session.windows}w`}</Text>
        {session.attached && <Text color="green">{" ●"}</Text>}
        <AgentChip label="C" state={session.claude} />
        <AgentChip label="X" state={session.codex} />
      </Text>
      <Text dimColor wrap="truncate-end">
        {summary}
      </Text>
    </Box>
  );
}

/** Branch glyph and PR number, coloured by PR state; empty when there is none. */
function PrChip({ pr }: { pr: Session["pr"] }) {
  if (!pr.state) return null;
  const color =
    pr.state === "MERGED"
      ? "magenta"
      : pr.state === "CLOSED"
        ? "red"
        : pr.isDraft
          ? "gray"
          : "green";
  return (
    <Text color={color}>
      {` #${pr.number}`}
      {pr.isDraft ? " draft" : ""}
    </Text>
  );
}

/**
 * Agent run state, fed by the Claude/Codex lifecycle hooks via
 * set-agent-state.sh. Idle and finished agents render nothing.
 */
function AgentChip({ label, state }: { label: string; state: string }) {
  if (state === "working") return <Text color="cyan">{`  ${label}▶`}</Text>;
  if (state === "waiting") return <Text color="red">{`  ${label}!`}</Text>;
  return null;
}

function main() {
  if (!SWITCHER) {
    process.stderr.write(
      "session-board: $SESSION_SWITCHER is unset — launch via session-board.sh\n",
    );
    process.exit(1);
  }
  execFile(SWITCHER, ["--stages"], (error, text) => {
    if (error) {
      process.stderr.write(`session-board: ${error.message}\n`);
      process.exit(1);
    }
    const stages = text.trim().split("\n").filter(Boolean);
    render(<Board stages={stages} />);
  });
}

main();
