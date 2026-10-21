import router from '@system.router';

// Splash screen: loading a heavy page while the app starts can freeze the watch, so the game opens afterwards.
export default {
    data: {},
    onShow() {
        setTimeout(function () {
            router.replace({ uri: 'pages/game/game' });
        }, 400);
    }
};
