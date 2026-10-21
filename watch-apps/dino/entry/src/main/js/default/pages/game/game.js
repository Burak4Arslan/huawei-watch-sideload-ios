// Screen 466x466, ground line at y=300. Physics runs in seconds: if the watch slows down, the game does not.
var GROUND_Y = 300;
var DINO_X = 60;
var DINO_TOP = GROUND_Y - 60 + 2;
var JUMP_V = -800;
var SHORT_HOP_V = -350;
var GRAVITY = 2700;
var START_SPEED = 250;
var ACCEL = 7;
var MAX_SPEED = 560;
var NIGHT_EVERY = 700;
var FRAME_MS = 25;
var SHOW_FPS = false;   // shows frames per second on the game over screen; turn on only when measuring
var DAY = { bg: 0xF7F7F7, ink: 0x535353 };
var NIGHT = { bg: 0x202124, ink: 0xC8C8C8 };

// The dinosaur's hit boxes (inside the image): head, body, legs
var DINO_BOXES = [[30, 0, 58, 18], [6, 18, 44, 44], [14, 44, 36, 58]];

var TYPES = [
    { name: 'cactus-s1', w: 27, h: 51, from: 0 },
    { name: 'cactus-l1', w: 39, h: 60, from: 0 },
    { name: 'cactus-s2', w: 57, h: 51, from: 60 },
    { name: 'cactus-l2', w: 81, h: 60, from: 150 },
    { name: 'cactus-s3', w: 87, h: 51, from: 250 },
    { name: 'bird', w: 44, h: 28, from: 300, bird: true }
];

var game = {
    state: 'ready',
    y: DINO_TOP,
    vy: 0,
    speed: START_SPEED,
    runTime: 0,
    score: 0,
    shown: -1,
    hi: 0,
    night: false,
    obstacles: [],
    clouds: [{ x: 300, y: 120 }, { x: 520, y: 170 }],
    groundOffset: 0,
    runTimer: 0,
    runFrame: 0,
    birdTimer: 0,
    birdFrame: 1,
    timer: null,
    last: 0,
    frames: 0,
    playStart: 0,
    overAt: 0,
    lastPress: 0
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

function loadHi(done) {
    var storage = system('@system.storage');
    try {
        storage.get({
            key: 'hi',
            default: '0',
            success: function (value) { done(parseInt(value, 10) || 0); },
            fail: function () { done(0); }
        });
    } catch (e) { done(0); }
}

function saveHi(hi) {
    var storage = system('@system.storage');
    try { storage.set({ key: 'hi', value: String(hi) }); } catch (e) {}
}

function image(name) {
    return '/common/images/' + name + (game.night ? '-n' : '') + '.png';
}

function pad(value) {
    var text = String(Math.floor(value));
    while (text.length < 5) { text = '0' + text; }
    return text;
}

function pickType() {
    var choices = [];
    var bird = null;
    for (var i = 0; i < TYPES.length; i++) {
        if (TYPES[i].from <= game.score) {
            if (TYPES[i].bird) { bird = TYPES[i]; } else { choices.push(TYPES[i]); }
        }
    }
    if (bird && Math.random() < 0.2) { return bird; }
    return choices[Math.floor(Math.random() * choices.length)];
}

// Enough room to land and jump again; the gap grows with the speed
function gapAfter() {
    return game.speed * (0.75 + Math.random() * 0.75) + 40;
}

export default {
    data: {
        state: 'ready',
        bg: DAY.bg,
        ink: DAY.ink,
        night: false,
        cloudSrc: '/common/images/cloud.png',
        groundSrc: '/common/images/ground.png',
        c0x: 300,
        c0y: 120,
        c1x: 520,
        c1y: 170,
        groundX: 0,
        o0src: '/common/images/cactus-s1.png',
        o0x: 700,
        o0y: 252,
        o0w: 27,
        o0h: 51,
        o1src: '/common/images/cactus-s1.png',
        o1x: 1000,
        o1y: 252,
        o1w: 27,
        o1h: 51,
        o2src: '/common/images/cactus-s1.png',
        o2x: 1300,
        o2y: 252,
        o2w: 27,
        o2h: 51,
        dinoSrc: '/common/images/dino-stand.png',
        dinoY: DINO_TOP,
        scoreText: '00000',
        fpsText: '',
        showFps: SHOW_FPS
    },
    onInit() {
        var that = this;
        this.reset();
        loadHi(function (hi) {
            game.hi = hi;
            that.showScore(true);
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
    set(name, value) {
        if (this[name] !== value) { this[name] = value; }
    },
    reset() {
        game.state = 'ready';
        game.y = DINO_TOP;
        game.vy = 0;
        game.speed = START_SPEED;
        game.runTime = 0;
        game.score = 0;
        game.obstacles = [];
        var x = 700;
        for (var i = 0; i < 3; i++) {
            game.obstacles.push({ x: x, type: TYPES[0], y: 0 });
            this.respawn(i, x);
            x = game.obstacles[i].x + game.obstacles[i].type.w + gapAfter();
        }
        this.setNight(false);
        this.state = 'ready';
        this.dinoY = DINO_TOP;
        this.dinoSrc = image('dino-stand');
        this.showScore(true);
    },
    respawn(i, x) {
        var obstacle = game.obstacles[i];
        var type = pickType();
        obstacle.type = type;
        obstacle.x = x;
        if (type.bird) {
            obstacle.y = Math.random() < 0.5 ? GROUND_Y - 24 - type.h : GROUND_Y - 72 - type.h;
        } else {
            obstacle.y = GROUND_Y + 3 - type.h;
        }
        var src = this.obstacleImage(obstacle);
        if (i === 0) { this.o0src = src; this.o0y = obstacle.y; this.o0w = type.w; this.o0h = type.h; }
        if (i === 1) { this.o1src = src; this.o1y = obstacle.y; this.o1w = type.w; this.o1h = type.h; }
        if (i === 2) { this.o2src = src; this.o2y = obstacle.y; this.o2w = type.w; this.o2h = type.h; }
        this.moveObstacle(i);
    },
    obstacleImage(obstacle) {
        return image(obstacle.type.bird ? 'bird-' + game.birdFrame : obstacle.type.name);
    },
    moveObstacle(i) {
        var x = Math.round(game.obstacles[i].x);
        if (i === 0) { this.set('o0x', x); }
        if (i === 1) { this.set('o1x', x); }
        if (i === 2) { this.set('o2x', x); }
    },
    refreshObstacleImages(birdsOnly) {
        for (var i = 0; i < 3; i++) {
            var obstacle = game.obstacles[i];
            if (birdsOnly && !obstacle.type.bird) { continue; }
            var src = this.obstacleImage(obstacle);
            if (i === 0) { this.set('o0src', src); }
            if (i === 1) { this.set('o1src', src); }
            if (i === 2) { this.set('o2src', src); }
        }
    },
    setNight(night) {
        game.night = night;
        var colors = night ? NIGHT : DAY;
        this.night = night;
        this.bg = colors.bg;
        this.ink = colors.ink;
        this.cloudSrc = image('cloud');
        this.groundSrc = image('ground');
        this.refreshObstacleImages(false);
        if (game.state !== 'over') {
            this.dinoSrc = image(game.state === 'play' ? 'dino-run1' : 'dino-stand');
        }
    },
    showScore(force) {
        var whole = Math.floor(game.score);
        if (!force && whole === game.shown) { return; }
        game.shown = whole;
        this.scoreText = (game.hi > 0 ? 'HI ' + pad(game.hi) + '   ' : '') + pad(whole);
    },
    // Jump as soon as the finger touches; lift early for a short jump. click is the fallback if the watch sends no touchstart.
    press() {
        game.lastPress = Date.now();
        this.act();
    },
    release() {
        if (game.state === 'play' && game.vy < SHORT_HOP_V) {
            game.vy = SHORT_HOP_V;
        }
    },
    tap() {
        if (Date.now() - game.lastPress < 500) {
            return;
        }
        this.act();
    },
    act() {
        if (game.state === 'ready') {
            this.start();
            this.jump();
        } else if (game.state === 'play') {
            this.jump();
        } else if (game.state === 'over' && Date.now() - game.overAt > 500) {
            this.reset();
            this.start();
        }
    },
    start() {
        game.state = 'play';
        game.frames = 0;
        game.playStart = Date.now();
        this.state = 'play';
    },
    jump() {
        if (game.y >= DINO_TOP - 0.5) {
            game.vy = JUMP_V;
            this.dinoSrc = image('dino-stand');
        }
    },
    tick() {
        var now = Date.now();
        var dt = Math.min(0.05, (now - game.last) / 1000);
        game.last = now;

        if (game.state === 'over') {
            return;
        }

        // Clouds drift slowly on the ready screen too
        for (var c = 0; c < 2; c++) {
            var cloud = game.clouds[c];
            cloud.x -= 25 * dt;
            if (cloud.x < -50) {
                cloud.x = 480 + Math.random() * 100;
                cloud.y = Math.round(90 + Math.random() * 110);
                if (c === 0) { this.c0y = cloud.y; } else { this.c1y = cloud.y; }
            }
        }
        this.set('c0x', Math.round(game.clouds[0].x));
        this.set('c1x', Math.round(game.clouds[1].x));

        if (game.state === 'ready') {
            return;
        }

        game.frames++;
        game.runTime += dt;
        game.speed = Math.min(MAX_SPEED, START_SPEED + ACCEL * game.runTime);
        game.score += game.speed * dt / 25;
        if (game.score > 99999) { game.score = 99999; }
        this.showScore(false);
        var night = Math.floor(game.score / NIGHT_EVERY) % 2 === 1;
        if (night !== game.night) {
            this.setNight(night);
        }

        // Dinosaur
        if (game.vy !== 0 || game.y < DINO_TOP) {
            game.vy += GRAVITY * dt;
            game.y += game.vy * dt;
            if (game.y >= DINO_TOP) {
                game.y = DINO_TOP;
                game.vy = 0;
            }
            this.set('dinoY', Math.round(game.y));
        } else {
            game.runTimer += dt;
            if (game.runTimer > 0.1) {
                game.runTimer = 0;
                game.runFrame = 1 - game.runFrame;
                this.dinoSrc = image(game.runFrame === 0 ? 'dino-run1' : 'dino-run2');
            }
        }

        // Ground
        game.groundOffset = (game.groundOffset + game.speed * dt) % 100;
        this.set('groundX', -Math.round(game.groundOffset));

        // Birds' wings
        game.birdTimer += dt;
        if (game.birdTimer > 0.18) {
            game.birdTimer = 0;
            game.birdFrame = game.birdFrame === 1 ? 2 : 1;
            this.refreshObstacleImages(true);
        }

        // Obstacles and collisions
        var hit = false;
        var i;
        for (i = 0; i < 3; i++) {
            var obstacle = game.obstacles[i];
            obstacle.x -= game.speed * dt;
            if (obstacle.x + obstacle.type.w < -10) {
                var right = 0;
                for (var j = 0; j < 3; j++) {
                    if (j !== i) { right = Math.max(right, game.obstacles[j].x + game.obstacles[j].type.w); }
                }
                this.respawn(i, Math.max(right + gapAfter(), 480));
            } else {
                this.moveObstacle(i);
            }
            if (this.collides(obstacle)) { hit = true; }
        }

        if (hit) {
            this.gameOver(now);
        }
    },
    collides(obstacle) {
        var inset = obstacle.type.bird ? 6 : 4;
        var left = obstacle.x + inset;
        var right = obstacle.x + obstacle.type.w - inset;
        var top = obstacle.y + inset;
        var bottom = obstacle.y + obstacle.type.h - inset;
        if (right < DINO_X || left > DINO_X + 60) { return false; }
        for (var b = 0; b < DINO_BOXES.length; b++) {
            var box = DINO_BOXES[b];
            if (DINO_X + box[2] > left && DINO_X + box[0] < right &&
                game.y + box[3] > top && game.y + box[1] < bottom) {
                return true;
            }
        }
        return false;
    },
    gameOver(now) {
        buzz();
        game.state = 'over';
        game.overAt = now;
        var seconds = Math.max(0.5, (now - game.playStart) / 1000);
        if (Math.floor(game.score) > game.hi) {
            game.hi = Math.floor(game.score);
            saveHi(game.hi);
        }
        this.dinoSrc = image('dino-dead');
        this.showScore(true);
        this.fpsText = Math.round(game.frames / seconds) + ' fps';
        this.state = 'over';
    }
};
