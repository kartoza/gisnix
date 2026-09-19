# Shared kanata layer/mod/nav config: home-row mods (GACS, long-hold to
# arm), the space/menu navigation+mouse layer, and the transparent meta
# layer used for RGB feedback. Parameterised by the chord file so a
# multi-keyboard setup can run a second instance with its own chord set on
# a different board.
{
  # Timing for the space/menu → navigation-layer hold (kept snappy).
  tapTimeout ? 280,
  holdTimeout ? 280,
  # Home-row mods are plain tap-hold: tap = letter, hold >= modHoldTimeout ms =
  # the modifier. Holding two mods together stacks them (d+f = Ctrl+Shift), and
  # a held mod applies to whatever key you press next (either hand). The hold
  # window IS the misfire guard — nothing is held that long during normal
  # typing, so ordinary keystrokes stay letters. modHoldTimeout is the SINGLE
  # global hold timeout (tune here). modTapTimeout is the tap-repress window:
  # double-tap then hold a mod key within it to autorepeat its LETTER.
  modTapTimeout ? 200,
  modHoldTimeout ? 500,
  # Optional per-layout BRACKET chord file (no defchordsv2 wrapper — just
  # the bracket lines themselves). null = no chords at all, the default:
  # gisnix ships the layer/mod/nav mechanism but no opinionated chord set —
  # write your own and point this at it.
  chordsFile ? null,
  # Optional bigram -> n-gram expansion chord lines, spliced into the same
  # defchordsv2 block (kanata allows exactly one per config). null = none.
  expansionsFile ? null,
  # Opt-in third layer: hold this key, and hjkl drive herdr. null = off.
  # The key is the caller's choice because the right one differs by board —
  # the Glove80 uses `bspc` to match the Sonsei's own superkey 22, while a
  # keyboard with a Caps Lock uses `caps`, which costs nothing anyone wants.
  # Whatever is named here keeps its normal action on TAP; only the hold is
  # taken. See the layer comment below.
  herdrKey ? null,
  # Opt-in clipboard holds on x/c/v, transcribed from the Sonsei's superkeys
  # 9/20/21: tap the letter, hold it for the clipboard action. Note the
  # asymmetry is the Sonsei's own — copy is Ctrl+C (not Ctrl+Shift+C) while
  # paste is Ctrl+Shift+V, so paste works in a terminal but hold-c in one
  # sends SIGINT. Kept faithful rather than corrected.
  clipboardHolds ? false,
  # Opt-in: the herdr layer's `e` (mnemonic: email) types the LOGGED-IN
  # user's address. The value is the store path of a script that resolves
  # the active seat0 session to a user and prints their email address as
  # keycodes (kanata runs it at press time via `cmd-output-keys`), so the
  # same key types the right address under each account on a shared
  # machine. Requires a cmd-enabled kanata (build kanata-with-cmd) and
  # `danger-enable-cmd yes` in the instance's defcfg — the caller providing
  # this script must provide that too. null = no binding.
  emailScript ? null,
  # Which xkb layout the keyboards on this instance type under. kanata sends
  # KEYCODES, not characters, so anything whose keycode moves between layouts
  # has to be chosen here — today that is only `@`, which is AltGr+2 on pt-PT
  # and Shift+2 on US.
  #
  # MUST agree with chordsFile, if one is given: the chord outputs are
  # keycodes for a specific layout, so the two are one fact stated twice.
  layout ? "us",
}:
let
  herdrLayer = herdrKey != null;

  # defchordsv2 is only legal ONCE per config, and only if there is at
  # least one chord in it — an empty block is invalid kanata syntax. So the
  # whole thing is omitted when neither file is given, rather than pointed
  # at an empty placeholder.
  chordsBlock =
    if chordsFile == null && expansionsFile == null then
      ""
    else
      ''

        ;; Chords — exactly one defchordsv2 is allowed, so the bracket
        ;; lines and the expansion lines are spliced into a single block.
        (defchordsv2
        ${if chordsFile != null then builtins.readFile chordsFile else ""}
        ${if expansionsFile != null then builtins.readFile expansionsFile else ""}
        )'';

  # The trigger slot only exists in defsrc when the layer is on, so every
  # deflayer must gain or lose a column in step with it. One definition
  # each, rather than four places to forget.
  # Bottom row: x/c/v gain a hold action only when clipboardHolds is on, so
  # the row is written once rather than branched.
  cutKey = if clipboardHolds then "@cut" else "x";
  copyKey = if clipboardHolds then "@copy" else "c";
  pasteKey = if clipboardHolds then "@paste" else "v";

  clipboardAliases =
    if !clipboardHolds then
      ""
    else
      ''

        ;; Clipboard holds — same tap/hold windows as the home-row mods, so
        ;; there is one hold feel across the board and one number to tune.
        ;; Alias names avoid x/c/v so they cannot be mistaken for the letters.
        cut   (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} x C-x)
        copy  (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} c C-c)
        paste (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} v C-S-v)
      '';

  # `:` opens aerc's command line, and it moves between layouts:
  # pt-PT shifts the `.` key, US shifts the `;` key.
  colonChord = if layout == "pt" then "S-." else "S-;";

  # `-` appears in every multi-word aerc command (`:next-folder`,
  # `:switch-account -n`). pt-PT puts it where US puts `/`; US has its own
  # `min` key. Same drift as `:` and `@`, same fix.
  dashChord = if layout == "pt" then "/" else "min";

  emailAlias =
    if emailScript == null then
      ""
    else
      ''

        ;; Types the logged-in user's email address. Resolved at PRESS time:
        ;; kanata runs the script and presses whatever keycodes it prints
        ;; (a key S-expression, macro-style). The layout argument rides
        ;; along because the script does its own @/- keycode selection —
        ;; the character-mapping philosophy (refuse rather than guess)
        ;; lives in dotfiles/scripts/kanata-type-email.sh with the mapping.
        email (cmd-output-keys ${emailScript} ${layout})
      '';

  emailInLayer = if emailScript == null then "_" else "@email";

  herdrSrc = if herdrLayer then " ${herdrKey}" else "";
  herdrDefault = if herdrLayer then " @herdr-nav" else "";
  herdrPass = if herdrLayer then " _" else "";

  # Tab rides the same gate: holding it opens the aerc layer, which only
  # exists when the macro layers do. Same three-way split as the trigger
  # key — a defsrc column, its action on the base layer, and a transparent
  # slot on every other layer.
  tabSrc = if herdrLayer then " tab" else "";
  tabDefault = if herdrLayer then " @tab-aerc" else "";
  tabPass = if herdrLayer then " _" else "";

  # The main typing layer. There used to be a second stamped copy of it
  # (`default-aerc`, the polymorphic-base era — see the herdr comment
  # below); with the aerc layer on its own Tab hold there is exactly one
  # base again, so it is written out plainly.
  defaultLayer = ''
    (deflayer default
        q w e r t    y u i o p
        @a @s @d @f g    h @j @k @l @;
        z ${cutKey} ${copyKey} ${pasteKey} b    n m , . /
        @spc-nav @menu-nav @met${herdrDefault}${tabDefault}
      )'';

  # The herdr layer. hjkl are transcribed from the Sonsei's layer 2 ("Macros
  # & Symbols") — hosts/abyss/sonsei-layout.json macros 2-5, which sit on that
  # board's h/j/k/l. herdr's keys are tmux-shaped: Ctrl+b is the prefix, p/n
  # step tabs, and w opens the workspace picker, driven with an arrow + Enter.
  #
  #   h -> previous tab        C-b p
  #   j -> next workspace      C-b w, down, enter
  #   k -> previous workspace  C-b w, up, enter
  #   l -> next tab            C-b n
  #   u -> DOWN the agent list C-b i   (herdr's "next agent")
  #   i -> UP the agent list   C-b u   (herdr's "previous agent")
  #   n -> new tab             C-b c
  #   e -> types your email    (only when `emailScript` is set)
  #
  # `e` is the email key — THE MNEMONIC IS THE LETTER, the same rule s and a
  # follow below. It lived on `t` first (no mnemonic, just a free key); it
  # moved when the address became per-user, which was the natural moment to
  # retrain one finger. `t` is transparent again and free for the next macro.
  #
  # `n` is on the bottom row, away from the h/l tab keys, and stays there
  # even now that `t` is free: it is the letter herdr's own `next tab`
  # already uses, so the row reads as tab-ish, and moving a settled binding
  # costs more than the empty key it would tidy away.
  #
  # `e` is not a herdr key at all. The layer is named for what first lived on
  # it, but the Sonsei calls its equivalent "Macros & Symbols", which is the
  # honest description of what it now is: the place a held key reaches a
  # macro. Adding more of them here is expected.
  #
  # THE AERC LAYER IS ON TAB, NOT ON THIS TRIGGER — and every aerc verb
  # lives ONLY there, including the s/a mail-filing pair (they sat on this
  # layer too at first, but filing mail is meaningless outside aerc and a
  # herdr-layer key that types `:move Spam` into a terminal is a hazard,
  # not a shortcut). Holding Tab opens the aerc layer from anywhere — see
  # the aerc deflayer below for the full key table (it has grown past
  # what fits in one sentence here). This
  # REPLACES the polymorphic-base era, where a kitty focus watcher flipped
  # the base layer over TCP so the herdr trigger meant "drive aerc" while
  # aerc was focused — the detection never fired reliably (the macros
  # simply didn't run), and a second held key that always works beats one
  # clever key that mostly doesn't. Do not resurrect the watcher; if aerc
  # macros misbehave now, the fault is in the macros, not in detection.
  #
  # u and i are ours, not the Sonsei's, and they are the one pair here that
  # depends on configuration rather than on herdr's defaults: herdr ships
  # `previous agent` and `next agent` UNBOUND, so dotfiles/herdr/config.toml
  # binds them to prefix+u and prefix+i for these macros to have something to
  # send. Change one without the other and the key goes quiet. They sit above
  # j and k, so the agent pair is one row up from the workspace pair.
  #
  # The COLUMN sets the direction, not the letter. j moves down the workspace
  # picker, so u on top of it moves DOWN the agent list; k moves up, so i
  # moves UP. The pair first shipped the other way round, reading h/l's
  # left-is-previous sense across the row, and each column then disagreed with
  # itself: the finger moved down a row and the list moved the opposite way.
  # h/l keep the horizontal reading because they are a horizontal pair; u/i
  # are read vertically, against the keys underneath them.
  #
  # Say "down the list", not "next agent", when changing this. Whether next is
  # up or down is a fact about herdr's list order that no name here reveals,
  # and guessing it wrong is how the pair got inverted in the first place.
  #
  # WHY AN ORDINARY KEY AND NOT A MODIFIER. A modifier cannot trigger this
  # layer at all: kanata cannot suppress a physically-held modifier while a
  # macro sends its own (`unmod` drops modifiers but cannot add one, and
  # nests inside neither `multi` nor `macro`), so holding Alt would make the
  # prefix Ctrl+Alt+b and herdr would ignore all four macros. The trigger
  # therefore has to be a normal key whose hold we borrow.
  #
  # WHICH normal key is the caller's to pick, because the cost differs by
  # board. On the Glove80 it is `bspc`, which is what the Sonsei itself does
  # — superkey 22 is tap Backspace / hold shift-to-layer-2, the very layer
  # these macros live on, exactly as its Space superkey shifts to the Cursor
  # layer kanata already mirrors as the nav layer. The price there is that
  # holding Backspace no longer repeats a delete; double-tap and hold within
  # tapTimeout to autorepeat instead, the same escape the home-row mods use.
  #
  # On a board with a Caps Lock there is a better answer: `caps` gives up
  # nothing, since nobody holds Caps Lock on purpose. A tap still toggles
  # caps, so the key keeps its stated function.
  #
  # The 25 ms pause is the one deviation from the Sonsei, which has none: the
  # Dygma sends from firmware, kanata sends through uinput considerably
  # faster, and the picker has to be on screen before it can take an arrow.
  herdrDeflayer =
    if !herdrLayer then
      ""
    else
      ''

        ;; herdr layer — held via the trigger key. Everything but hjkl is
        ;; transparent, so the rest of the board behaves as normal.
        (deflayer herdr
          _ _ ${emailInLayer} _ _    _ @herdr-agent-down @herdr-agent-up _ _
          _ _ _ _ _    @herdr-left @herdr-down @herdr-up @herdr-right _
          _ _ _ _ _    @herdr-new-tab _ _ _ _
          _ _ _ _ _
        )

        ;; aerc layer — held via Tab (see @tab-aerc). Every key here is a
        ;; typed aerc command (colon-chord + word + Enter), the same
        ;; philosophy s/a and the nav macros already established: it works
        ;; regardless of what binds.conf says, and it reads back as
        ;; exactly what it does. hjkl keep the direction philosophy from
        ;; the herdr layer: h/l are the horizontal pair (left = previous
        ;; account, right = next), j/k read vertically against the folder
        ;; sidebar (j down = next folder, k up = previous).
        ;;
        ;;   h/l -> switch account (prev/next)   :prev-tab / :next-tab
        ;;   j/k -> switch folder (next/prev)    :next-folder / :prev-folder
        ;;   s/a -> file to Spam/Archive         :move Spam / :move Archive
        ;;   r   -> reply-ALL (aerc's `rr`)      :reply -a
        ;;   e   -> types the logged-in user's email (see below)
        ;;   c   -> compose a new message        :compose
        ;;   f   -> forward the selected message :forward
        ;;   d   -> delete the selected message  :delete
        ;;   g   -> reopen a postponed draft     :recall
        ;;   y   -> show/hide full headers       :toggle-headers
        ;;   u   -> toggle read/unread           :flag -tx seen
        ;;   i   -> toggle the star/flag         :flag -tx flagged
        ;;   m   -> enter/leave visual mark mode :mark -v
        ;;   v/b -> PRIME (not send) :search / :filter — see below
        ;;   n   -> add this message's sender as a contact (khard)
        ;;   o   -> browse/edit contacts (khard)
        ;;
        ;; c/f/d/v cost something real: they take over a key that has a
        ;; hold-behaviour on the base layer (copy/Shift/Ctrl/paste) WHILE
        ;; TAB IS HELD — the same trade a/s already made for Super/Alt.
        ;; Losing hold-to-copy specifically while composing/forwarding is
        ;; the one to watch; move c or v to a free key (q/w/t/p/z/x) if
        ;; that bites — the layer is nearly full now.
        ;;
        ;; v and b are a DIFFERENT kind of macro: they type `:search ` /
        ;; `:filter ` and stop WITHOUT Enter, leaving the aerc command line
        ;; open with the cursor after the trailing space — a primer, not a
        ;; command. You type the search terms yourself and press Enter.
        ;;
        ;; m's exact flag is a considered choice, not a typo: `:mark`'s
        ;; own syntax block lists a <filter> argument, but its -v flag
        ;; ("Enter / leave visual mark mode") is documented as taking
        ;; none — the only mark variant safe to send blind from a macro.
        ;;
        ;; n and o are CONTACTS, via khard (dotfiles/khard/config) — see
        ;; the aliases below for exactly what each pipes/opens, and why
        ;; this is a separate concern from address-book autocomplete
        ;; (which needs no macro: it is a plain Tab-tap in the composer,
        ;; wired through accounts.conf's address-book-cmd).
        (deflayer aerc
          _ _ ${emailInLayer} @aerc-reply _    @aerc-headers @aerc-unread @aerc-flag @aerc-contact-edit _
          @aerc-archive @aerc-spam @aerc-delete @aerc-forward @aerc-recall    @aerc-acct-prev @aerc-folder-next @aerc-folder-prev @aerc-acct-next _
          _ _ @aerc-compose @aerc-search @aerc-filter    @aerc-contact-add @aerc-mark _ _ _
          _ _ _ _ _
        )
      '';

  herdrAliases =
    if !herdrLayer then
      ""
    else
      ''

        ;; herdr navigation — alias names match the Sonsei's Bazecor macro
        ;; names, so the two keyboards can be diffed against each other.
        herdr-nav   (tap-hold ${toString tapTimeout} ${toString holdTimeout} ${herdrKey} (layer-while-held herdr))
        herdr-left  (macro C-b p)
        herdr-down  (macro C-b w 25 down ret)
        herdr-up    (macro C-b w 25 up ret)
        herdr-right (macro C-b n)
        ;; Agents. No picker to wait for, so no 25 ms pause — these step
        ;; straight, the way the tab macros do.
        ;;
        ;; Named for the direction the list moves, not for herdr's own
        ;; "previous/next agent". Those two words are the reason this pair
        ;; was hard to check by reading: which of them is up is a fact about
        ;; herdr's list order, not something the name tells you. Measured, not
        ;; guessed — prefix+u moves UP the list, prefix+i moves DOWN.
        ;;
        ;; THE LETTERS DELIBERATELY DO NOT MATCH. Physical u sends C-b i.
        ;; dotfiles/herdr/config.toml binds previous_agent to prefix+u and
        ;; next_agent to prefix+i, and that file is a running herdr's contract:
        ;; it is read once at startup, so changing it cannot take effect
        ;; without restarting a process that may be holding live work. The
        ;; direction therefore gets fixed on this side, where a rebuild
        ;; restarts kanata and nothing else. Leave config.toml alone.
        herdr-agent-down (macro C-b i)
        herdr-agent-up   (macro C-b u)
        ;; New tab. C-b c is a herdr default, so nothing binds it here — the
        ;; rule in config.toml is to send the defaults, never rebind them.
        herdr-new-tab    (macro C-b c)
        ;; aerc mail filing — named for the destination folder, which is
        ;; also the trigger letter's mnemonic. Keycodes, so the `:` and the
        ;; capital letters are layout/shift chords; the trailing ret runs
        ;; the command, filing the selected message in one held keypress.
        aerc-spam    (macro ${colonChord} m o v e spc S-s p a m ret)
        aerc-archive (macro ${colonChord} m o v e spc S-a r c h i v e ret)
        ;; Reply-ALL — typed as `:reply -a`, the command aerc's own `rr`
        ;; default keybind runs (r then r). REPLY-ALL IS THE DEFAULT HERE,
        ;; deliberately: aerc also ships `Rr` (Shift+R then r) for a PLAIN
        ;; reply to the sender only (`:reply`, no `-a`) — a different
        ;; default bind on a different key. One held key, one behaviour;
        ;; add a second key here if plain reply is ever wanted too.
        aerc-reply (macro ${colonChord} r e p l y spc ${dashChord} a ret)
        ;; The aerc layer's trigger — hold Tab. A tap still types Tab, and
        ;; Alt+Tab window switching is untouched (the switcher TAPS tab
        ;; while Alt is held; nobody holds tab itself past the window).
        ;; What IS given up is hold-Tab-to-autorepeat, with the same escape
        ;; every tap-hold here has: double-tap and hold within tapTimeout.
        tab-aerc (tap-hold ${toString tapTimeout} ${toString holdTimeout} tab (layer-while-held aerc))
        ;; aerc navigation — typed commands rather than aerc's default
        ;; keybinds, so they work whatever binds.conf says and read back as
        ;; exactly what they do. `:` and `-` go via colonChord/dashChord
        ;; because both keycodes move between the pt-PT and US layouts.
        ;; Accounts are TABS in aerc, so switching account is :prev-tab /
        ;; :next-tab — the first version typed `:switch-account -p/-n`,
        ;; which is not what aerc calls it, and the command line just
        ;; errored. The verbs h/l send are tab verbs, the mental model
        ;; (h/l step between accounts) is unchanged.
        aerc-acct-prev   (macro ${colonChord} p r e v ${dashChord} t a b ret)
        aerc-acct-next   (macro ${colonChord} n e x t ${dashChord} t a b ret)
        aerc-folder-next (macro ${colonChord} n e x t ${dashChord} f o l d e r ret)
        aerc-folder-prev (macro ${colonChord} p r e v ${dashChord} f o l d e r ret)
        ;; Message actions — no arguments, so each is safe to send blind
        ;; as a single held keypress.
        aerc-compose (macro ${colonChord} c o m p o s e ret)
        aerc-forward (macro ${colonChord} f o r w a r d ret)
        aerc-delete  (macro ${colonChord} d e l e t e ret)
        aerc-recall  (macro ${colonChord} r e c a l l ret)
        aerc-headers (macro ${colonChord} t o g g l e ${dashChord} h e a d e r s ret)
        ;; Status toggles — `:flag -tx <name>` sets a SPECIFIC named flag
        ;; (RFC 3501 §2.3.2 names, not a letter aerc invented); -t makes it
        ;; a toggle rather than an unconditional set.
        aerc-unread (macro ${colonChord} f l a g spc ${dashChord} t x spc s e e n ret)
        aerc-flag   (macro ${colonChord} f l a g spc ${dashChord} t x spc f l a g g e d ret)
        ;; Visual mark mode — `-v` is the one `:mark` variant documented
        ;; to need no <filter> argument, so it is the only one safe to
        ;; send blind from a macro; `-T`/plain `:mark` want a target.
        aerc-mark (macro ${colonChord} m a r k spc ${dashChord} v ret)
        ;; PRIMERS, not commands: type the verb and a trailing space, then
        ;; stop — no Enter. The aerc command line stays open with the
        ;; cursor after the space, for you to type search terms yourself.
        aerc-search (macro ${colonChord} s e a r c h spc)
        aerc-filter (macro ${colonChord} f i l t e r spc)
        ;; Contacts, via khard (dotfiles/khard/config, khard.dev). Not
        ;; address-book AUTOCOMPLETE — that already works from a plain tap
        ;; of Tab in the composer's To: field once accounts.conf sets
        ;; `address-book-cmd = khard email --remove-first-line --parsable
        ;; %s` (the man-page-documented pairing), needing no macro at all.
        ;; These two are the "manage" half: adding to and browsing the
        ;; book itself.
        ;;
        ;; Pipes the OPEN message's headers to `khard add-email`, which
        ;; parses the From: line and interactively offers to create a
        ;; contact or attach the address to an existing one. `:pipe`
        ;; (without -b) opens a real terminal tab for that prompt — this
        ;; is interactive by design, not a fire-and-forget macro.
        aerc-contact-add (macro ${colonChord} p i p e spc ${dashChord} m spc k h a r d spc a d d ${dashChord} e m a i l ret)
        ;; Opens a terminal tab running `khard edit` with no search term,
        ;; which lists every contact for interactive selection, then edits
        ;; the one you pick. Verified zero-arg-safe against khard 0.20.1
        ;; --help (empty search terms is the documented "show all" case).
        aerc-contact-edit (macro ${colonChord} t e r m spc k h a r d spc e d i t ret)${emailAlias}
      '';
in
''
  ;; Define the source keys we want to intercept
  ;; menu = the context-menu key (left of right Ctrl)
  ;; lmet = the physical Super key (for the meta lighting layer)
  ;; tab (macro-layer instances only) = tap Tab / hold for the aerc layer
  (defsrc
    q w e r t    y u i o p
    a s d f g    h j k l ;
    z x c v b    n m , . /
    spc menu lmet${herdrSrc}${tabSrc}
  )

  ;; Default layer with home row mods (long-hold to arm the modifier)
  ;; Left:  a=Super, s=Alt, d=Ctrl, f=Shift
  ;; Right: j=Shift, k=Ctrl, l=Alt, ;=Super
  ${defaultLayer}

  ;; Navigation/Mouse layer (activated by holding space or menu)
  ;; ESDF cluster so the left hand stays on its home position:
  ;; - esdf → mouse movement (e=up s=left d=down f=right)
  ;; - w/r → left/right click, t/g → scroll up/down
  ;; - hjkl → arrow keys (vim-style), n=home, uio=pgdn/pgup/end
  ;; Right-hand speed modifiers (hold while the left hand steers esdf):
  ;; - m → HALF (50%), , → QUARTER (25%), . → TENTH (10%)
  (deflayer navigation
    _ @lmb @mouse-up @rmb @scroll-up    _ pgdn pgup end _
    _ @mouse-left @mouse-down @mouse-right @scroll-down    left down up rght _
    _ _ _ _ _    home @spd-half @spd-quarter @spd-tenth _
    _ _ _${herdrPass}${tabPass}
  )

  ;; Meta layer: purely for lighting feedback. All keys are
  ;; transparent (Super shortcuts work as normal); entering and
  ;; leaving this layer fires TCP LayerChange events that the
  ;; razer-layer-lights listener uses to spotlight the meta binds.
  (deflayer meta
    _ _ _ _ _    _ _ _ _ _
    _ _ _ _ _    _ _ _ _ _
    _ _ _ _ _    _ _ _ _ _
    _ _ _${herdrPass}${tabPass}
  )${herdrDeflayer}

  ;; Alias definitions
  (defalias
    ;; Home row mods — plain tap-hold. Tap = letter; hold past modHoldTimeout =
    ;; the modifier. Hold two together to STACK (d+f = Ctrl+Shift); a held mod
    ;; then applies to the next key on either hand. The hold window is the whole
    ;; misfire guard — nothing is held that long during normal typing.
    ;; Left:  a=Super, s=Alt, d=Ctrl, f=Shift
    a (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} a (multi lmet (layer-while-held meta)))
    s (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} s lalt)
    d (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} d lctl)
    f (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} f lsft)

    ;; Right: j=Shift, k=Ctrl, l=Alt, ;=Super (j/k/l also carry chords)
    j (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} j rsft)
    k (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} k rctl)
    l (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} l ralt)
    ; (tap-hold ${toString modTapTimeout} ${toString modHoldTimeout} ; (multi rmet (layer-while-held meta)))

    ;; Space: tap for space, hold for navigation layer
    spc-nav (tap-hold ${toString tapTimeout} ${toString holdTimeout} spc (layer-while-held navigation))

    ;; Menu key: tap for context menu, hold for navigation/mouse layer
    menu-nav (tap-hold ${toString tapTimeout} ${toString holdTimeout} menu (layer-while-held navigation))

    ;; Physical Super: modifier as normal + the meta lighting layer
    met (multi lmet (layer-while-held meta))

    ;; Mouse movement — accelerating: starts slow for precision, ramps to fast.
    ;; movemouse-accel-DIR: interval(ms) accel-time(ms) min-px max-px
    ;;   every 4 ms, ramp from 3 px to 22 px over 350 ms of holding.
    ;; The base already moves far quicker than the old 1 px / 6 ms crawl; the
    ;; speed keys below scale it further at runtime.
    mouse-up (movemouse-accel-up 4 350 3 22)
    mouse-down (movemouse-accel-down 4 350 3 22)
    mouse-left (movemouse-accel-left 4 350 3 22)
    mouse-right (movemouse-accel-right 4 350 3 22)

    ;; Dynamic speed modifiers — hold (right hand) while steering (left hand).
    ;; movemouse-speed scales the movemouse min/max distance by a percentage for
    ;; as long as the key is held (100% = base). Progressive precision slow-downs:
    ;; m = half (50%), , = quarter (25%), . = tenth (10%, pixel-hunting).
    spd-half    (movemouse-speed 50)
    spd-quarter (movemouse-speed 25)
    spd-tenth   (movemouse-speed 10)

    ;; Mouse clicks
    lmb mlft
    rmb mrgt

    ;; Mouse scroll - interval(ms) distance
    scroll-up (mwheel-up 50 120)
    scroll-down (mwheel-down 50 120)${clipboardAliases}${herdrAliases}
  )

  ${chordsBlock}
''
