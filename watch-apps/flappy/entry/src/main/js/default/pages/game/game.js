import bridge from '../../common/bridge.js';

// Screen 466x466. Physics runs in seconds: if the watch slows down, the game does not, only the frame rate drops.
var GROUND_Y = 404;
var BIRD_X = 130;
var BIRD_W = 60;
var BIRD_H = 46;
var CAP_W = 92;
var CAP_H = 28;
var GAP = 180;
var SPACING = 230;
var GAP_MIN = 150;
var GAP_MAX = 272;
var SPEED = 145;
var GRAVITY = 1500;
var FLAP = -430;
var MAX_FALL = 620;
var FRAME_MS = 25;
var SHOW_FPS = false;   // shows frames per second on the game over screen; turn on only when measuring
var START_Y = 200;
var BIRDS = ['/common/images/bird0.png', '/common/images/bird1.png', '/common/images/bird2.png', '/common/images/bird1.png'];

// Per-frame state stays outside data binding; only what is shown on screen is written to data
var game = {
    state: 'ready',
    y: START_Y,
    vy: 0,
    pipes: [],
    score: 0,
    best: 0,
    timer: null,
    last: 0,
    clock: 0,
    wing: 0,
    wingTime: 0,
    frames: 0,
    playStart: 0,
    overAt: 0,
    lastPress: 0,
    linked: false
};

function system(name) {
    try { return requireModule(name); } catch (e) { return null; }
}

function keepScreenOn(value) {
    var brightness = system('@system.brightness');
    try { brightness.setKeepScreenOn({ keepScreenOn: value }); } catch (e) {}
}

function buzz() {
    var vibrator = system('@system.vibrator');
    try { vibrator.vibrate({ mode: 'short' }); } catch (e) {}
}

function loadBest(done) {
    var storage = system('@system.storage');
    try {
        storage.get({
            key: 'best',
            default: '0',
            success: function (value) { done(parseInt(value, 10) || 0); },
            fail: function () { done(0); }
        });
    } catch (e) { done(0); }
}

function saveBest(best) {
    var storage = system('@system.storage');
    try { storage.set({ key: 'best', value: String(best) }); } catch (e) {}
}

// Report the high score to the phone; the connection is opened at the first high score, not during play
function report(score, best) {
    try {
        if (!game.linked) {
            game.linked = true;
            bridge.start(function () {});
        }
        bridge.send({ t: 'flappy', s: score, b: best });
    } catch (e) {}
}

function randomGap() {
    return Math.round(GAP_MIN + Math.random() * (GAP_MAX - GAP_MIN));
}

function digitSrc(digit) {
    return '/common/images/n' + digit + '.png';
}

export default {
    data: {
        state: 'ready',
        birdY: START_Y,
        birdSrc: BIRDS[1],
        p0x: 560,
        p0top: 100,
        p0bottom: 76,
        p1x: 790,
        p1top: 100,
        p1bottom: 76,
        p2x: 1020,
        p2top: 100,
        p2bottom: 76,
        d0: '/common/images/n0.png',
        d1: '/common/images/n0.png',
        d2: '/common/images/n0.png',
        n0: false,
        n1: false,
        n2: false,
        x0: 0,
        x1: 0,
        x2: 0,
        bestText: '',
        scoreText: '',
        overTitle: '',
        fpsText: '',
        showFps: SHOW_FPS
    },
    onInit() {
        var that = this;
        this.reset();
        loadBest(function (best) {
            game.best = best;
            that.bestText = 'Best: ' + best;
        });
    },
    onShow() {
        var that = this;
        keepScreenOn(true);
        game.last = Date.now();
        if (game.timer === null) {
            game.timer = setInterval(function () { that.tick(); }, FRAME_MS);
        }
    },
    onHide() {
        this.stopLoop();
    },
    onDestroy() {
        this.stopLoop();
        keepScreenOn(false);
    },
    stopLoop() {
        if (game.timer !== null) {
            clearInterval(game.timer);
            game.timer = null;
        }
    },
    reset() {
        game.state = 'ready';
        game.y = START_Y;
        game.vy = 0;
        game.score = 0;
        game.pipes = [];
        for (var i = 0; i < 3; i++) {
            game.pipes.push({ x: 560 + i * SPACING, gap: randomGap(), passed: false });
            this.placePipe(i);
            this.movePipe(i);
        }
        this.state = 'ready';
        this.birdY = START_Y;
        this.n0 = false;
        this.n1 = false;
        this.n2 = false;
    },
    // Pipe body heights when the gap moves; a column always reaches the ground
    placePipe(i) {
        var pipe = game.pipes[i];
        var top = pipe.gap - GAP / 2 - CAP_H;
        var bottom = GROUND_Y - (pipe.gap + GAP / 2 + CAP_H);
        if (i === 0) { this.p0top = top; this.p0bottom = bottom; }
        if (i === 1) { this.p1top = top; this.p1bottom = bottom; }
        if (i === 2) { this.p2top = top; this.p2bottom = bottom; }
    },
    movePipe(i) {
        var x = Math.round(game.pipes[i].x);
        if (i === 0) { this.p0x = x; }
        if (i === 1) { this.p1x = x; }
        if (i === 2) { this.p2x = x; }
    },
    showScore(score) {
        var text = String(Math.min(score, 999));
        var width = text.length * 33 + (text.length - 1) * 2;
        var left = Math.round(233 - width / 2);
        this.n0 = text.length > 0;
        this.n1 = text.length > 1;
        this.n2 = text.length > 2;
        if (text.length > 0) { this.d0 = digitSrc(text.charAt(0)); this.x0 = left; }
        if (text.length > 1) { this.d1 = digitSrc(text.charAt(1)); this.x1 = left + 35; }
        if (text.length > 2) { this.d2 = digitSrc(text.charAt(2)); this.x2 = left + 70; }
    },
    // Flap as soon as the finger touches (touchstart). If the watch sends no touchstart, the click on release is the fallback;
    // if both arrive, the same tap is not counted twice.
    press() {
        game.lastPress = Date.now();
        this.act();
    },
    tap() {
        if (Date.now() - game.lastPress < 500) {
            return;
        }
        this.act();
    },
    act() {
        if (game.state === 'ready') {
            game.state = 'play';
            game.frames = 0;
            game.playStart = Date.now();
            game.vy = FLAP;
            this.state = 'play';
            this.showScore(0);
        } else if (game.state === 'play') {
            game.vy = FLAP;
        } else if (game.state === 'over' && Date.now() - game.overAt > 600) {
            this.reset();
        }
    },
    tick() {
        var now = Date.now();
        var dt = Math.min(0.06, (now - game.last) / 1000);
        game.last = now;
        game.clock += dt;

        if (game.state !== 'dying' && game.state !== 'over') {
            game.wingTime += dt;
            if (game.wingTime > 0.1) {
                game.wingTime = 0;
                game.wing = (game.wing + 1) % BIRDS.length;
                this.birdSrc = BIRDS[game.wing];
            }
        }

        if (game.state === 'ready') {
            this.birdY = Math.round(START_Y + 10 * Math.sin(game.clock * 4));
            return;
        }
        if (game.state === 'over') {
            return;
        }

        game.vy = Math.min(MAX_FALL, game.vy + GRAVITY * dt);
        game.y += game.vy * dt;
        if (game.y < -20) {
            game.y = -20;
            game.vy = 0;
        }

        if (game.state === 'dying') {
            if (game.y + BIRD_H - 4 >= GROUND_Y) {
                game.y = GROUND_Y - BIRD_H + 4;
                this.birdY = Math.round(game.y);
                this.gameOver(now);
                return;
            }
            this.birdY = Math.round(game.y);
            return;
        }

        game.frames++;
        var hit = game.y + BIRD_H - 4 >= GROUND_Y;
        var left = BIRD_X + 8;
        var right = BIRD_X + BIRD_W - 8;
        var top = game.y + 8;
        var bottom = game.y + BIRD_H - 8;
        var farthest = 0;
        var i;
        for (i = 0; i < 3; i++) {
            if (game.pipes[i].x > farthest) { farthest = game.pipes[i].x; }
        }
        for (i = 0; i < 3; i++) {
            var pipe = game.pipes[i];
            pipe.x -= SPEED * dt;
            if (pipe.x < -CAP_W) {
                pipe.x = farthest + SPACING;
                farthest = pipe.x;
                pipe.gap = randomGap();
                pipe.passed = false;
                this.placePipe(i);
            }
            this.movePipe(i);
            if (right > pipe.x + 4 && left < pipe.x + CAP_W - 4 &&
                (top < pipe.gap - GAP / 2 || bottom > pipe.gap + GAP / 2)) {
                hit = true;
            }
            if (!pipe.passed && pipe.x + CAP_W < left) {
                pipe.passed = true;
                game.score++;
                this.showScore(game.score);
            }
        }
        this.birdY = Math.round(game.y);

        if (hit) {
            buzz();
            game.state = 'dying';
            this.birdSrc = BIRDS[1];
            if (game.vy < 0) { game.vy = 0; }
        }
    },
    gameOver(now) {
        var seconds = Math.max(0.5, (now - game.playStart) / 1000);
        var record = game.score > game.best;
        if (record) {
            game.best = game.score;
            saveBest(game.best);
            report(game.score, game.best);
        }
        game.state = 'over';
        game.overAt = now;
        this.overTitle = record ? 'New best!' : 'Game over';
        this.scoreText = 'Score: ' + game.score;
        this.bestText = 'Best: ' + game.best;
        this.fpsText = Math.round(game.frames / seconds) + ' fps';
        this.state = 'over';
    }
};
