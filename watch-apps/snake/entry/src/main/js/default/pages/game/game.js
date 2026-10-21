// 21x21 grid of 22 px squares; the squares near the center are playable (a round arena up to the screen edge).
// No walls: leaving one edge enters from the opposite one. 40 squares because of the watch's JS memory (~1 KB each).
var CELL = 22;
var GRID = 21;
var OFFSET = 2;
var RADIUS = 212;
var POOL = 40;
var START_STEP = 0.17;
var MIN_STEP = 0.085;
var STEP_DROP = 0.004;
var FRAME_MS = 25;
var HIDDEN = -100;

var playable = [];
(function () {
    for (var r = 0; r < GRID; r++) {
        for (var c = 0; c < GRID; c++) {
            var dx = OFFSET + c * CELL + CELL / 2 - 233;
            var dy = OFFSET + r * CELL + CELL / 2 - 233;
            playable.push(dx * dx + dy * dy <= RADIUS * RADIUS);
        }
    }
})();

// body: head to tail {c, r, slot}; slot = the square on screen (s0..s79). free: unused squares
var game = {
    state: 'ready',
    body: [],
    free: [],
    dir: { x: 1, y: 0 },
    queue: [],
    food: { c: 0, r: 0 },
    score: 0,
    best: 0,
    stepTime: START_STEP,
    acc: 0,
    timer: null,
    last: 0,
    lastPress: 0,
    overAt: 0
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

// The tapped point: click has globalX/globalY, touchstart has point.x/y or touches[0]
function touchPoint(event) {
    if (!event) { return null; }
    if (event.globalX !== undefined) { return { x: event.globalX, y: event.globalY }; }
    if (event.point) { return { x: event.point.x, y: event.point.y }; }
    if (event.touches && event.touches[0]) { return { x: event.touches[0].globalX, y: event.touches[0].globalY }; }
    return null;
}

function pixel(cell) {
    return OFFSET + cell * CELL + 1;
}

function isPlayable(c, r) {
    return c >= 0 && r >= 0 && c < GRID && r < GRID && playable[r * GRID + c];
}

// Past the playable range of a row/column, enter from the other end
function wrap(c, r, dx, dy) {
    if (isPlayable(c, r)) { return { c: c, r: r }; }
    if (dx !== 0) {
        c = dx > 0 ? 0 : GRID - 1;
        while (!isPlayable(c, r)) { c += dx; }
    } else {
        r = dy > 0 ? 0 : GRID - 1;
        while (!isPlayable(c, r)) { r += dy; }
    }
    return { c: c, r: r };
}

function occupied(c, r, skipTail) {
    var last = skipTail ? game.body.length - 1 : game.body.length;
    for (var i = 0; i < last; i++) {
        if (game.body[i].c === c && game.body[i].r === r) { return true; }
    }
    return false;
}

var initial = {
    state: 'ready',
    foodX: HIDDEN,
    foodY: HIDDEN,
    eyeX: HIDDEN,
    eyeY: HIDDEN,
    scoreText: '0',
    resultText: '',
    bestText: ''
};
for (var slot = 0; slot < POOL; slot++) {
    initial['s' + slot + 'x'] = HIDDEN;
    initial['s' + slot + 'y'] = HIDDEN;
}

export default {
    data: initial,
    onInit() {
        var that = this;
        this.reset();
        loadBest(function (best) {
            game.best = best;
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
    place(slot, c, r) {
        this['s' + slot + 'x'] = c === null ? HIDDEN : pixel(c);
        this['s' + slot + 'y'] = c === null ? HIDDEN : pixel(r);
    },
    reset() {
        var i;
        for (i = 0; i < game.body.length; i++) {
            this.place(game.body[i].slot, null, null);
        }
        game.body = [];
        game.free = [];
        for (i = POOL - 1; i >= 4; i--) { game.free.push(i); }
        for (i = 0; i < 4; i++) {
            game.body.push({ c: 11 - i, r: 10, slot: i });
            this.place(i, 11 - i, 10);
        }
        game.dir = { x: 1, y: 0 };
        game.queue = [];
        game.score = 0;
        game.stepTime = START_STEP;
        game.acc = 0;
        game.state = 'ready';
        this.placeFood();
        this.moveEye();
        this.scoreText = '0';
        this.state = 'ready';
    },
    placeFood() {
        for (var tries = 0; tries < 300; tries++) {
            var c = Math.floor(Math.random() * GRID);
            var r = Math.floor(Math.random() * GRID);
            if (isPlayable(c, r) && !occupied(c, r, false)) {
                game.food = { c: c, r: r };
                this.foodX = pixel(c) + 3;
                this.foodY = pixel(r) + 3;
                return;
            }
        }
    },
    moveEye() {
        var head = game.body[0];
        this.eyeX = pixel(head.c) + 7 + game.dir.x * 4;
        this.eyeY = pixel(head.r) + 7 + game.dir.y * 4;
    },
    // Turn toward the tapped point relative to the head: up/down while moving sideways, left/right while moving vertically
    turnToward(event) {
        var point = touchPoint(event);
        if (point === null || game.queue.length >= 2) { return; }
        var last = game.queue.length > 0 ? game.queue[game.queue.length - 1] : game.dir;
        var head = game.body[0];
        if (last.x !== 0) {
            game.queue.push({ x: 0, y: point.y < pixel(head.r) + 10 ? -1 : 1 });
        } else {
            game.queue.push({ x: point.x < pixel(head.c) + 10 ? -1 : 1, y: 0 });
        }
    },
    // Turns as soon as the finger touches; click is the fallback if the watch sends no touchstart
    press(event) {
        game.lastPress = Date.now();
        this.act(event);
    },
    tap(event) {
        if (Date.now() - game.lastPress < 500) {
            return;
        }
        this.act(event);
    },
    act(event) {
        if (game.state === 'ready') {
            game.state = 'play';
            game.last = Date.now();
            this.state = 'play';
            this.turnToward(event);
        } else if (game.state === 'play') {
            this.turnToward(event);
        } else if (game.state === 'over' && Date.now() - game.overAt > 500) {
            this.reset();
        }
    },
    tick() {
        var now = Date.now();
        var dt = Math.min(0.1, (now - game.last) / 1000);
        game.last = now;
        if (game.state !== 'play') {
            return;
        }
        game.acc += dt;
        while (game.acc >= game.stepTime && game.state === 'play') {
            game.acc -= game.stepTime;
            this.step();
        }
    },
    step() {
        if (game.queue.length > 0) {
            game.dir = game.queue.shift();
        }
        var head = game.body[0];
        var next = wrap(head.c + game.dir.x, head.r + game.dir.y, game.dir.x, game.dir.y);
        var c = next.c;
        var r = next.r;
        var grow = c === game.food.c && r === game.food.r;
        if (occupied(c, r, !grow)) {
            this.die();
            return;
        }
        var slot;
        if (grow && game.free.length > 0) {
            slot = game.free.pop();
        } else {
            slot = game.body.pop().slot;
        }
        game.body.unshift({ c: c, r: r, slot: slot });
        this.place(slot, c, r);
        if (grow) {
            game.score++;
            game.stepTime = Math.max(MIN_STEP, game.stepTime - STEP_DROP);
            this.scoreText = String(game.score);
            this.placeFood();
        }
        this.moveEye();
    },
    die() {
        buzz();
        game.state = 'over';
        game.overAt = Date.now();
        if (game.score > game.best) {
            game.best = game.score;
            saveBest(game.best);
        }
        this.resultText = 'Score: ' + game.score;
        this.bestText = 'Best: ' + game.best;
        this.state = 'over';
    }
};
