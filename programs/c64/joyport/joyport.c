// Real joystick-port demo: joystick 2 ($DC00, active low) moves a cursor (reversed cell) that
// starts mid-screen. Fire on an empty cell draws balls, on a ball erases them, for as long as it is held. Q quits to BASIC.
#define SCREEN ((volatile char *)0x0400)
#define JOY (*(volatile char *)0xdc00)
#define RASTER (*(volatile char *)0xd012)
#define KEYS (*(volatile char *)0xc6)    // chars in the KERNAL keyboard buffer at $0277
#define BALL 81
#define DELAY 4                     // frames between cursor steps while held

int main(void) {
    char x = 20, y = 12, wait = 0, was = 0, pen = BALL;
    for (int i = 0; i < 1000; i++)
        SCREEN[i] = ' ';
    for (;;) {
        while (RASTER != 250) ;
        while (RASTER == 250) ;
        char j = ~JOY;
        int p = y * 40 + x;
        char c = SCREEN[p] & 0x7f;                          // cell without the cursor
        char fire = j & 16;
        if (fire && !was)
            pen = (c == BALL) ? ' ' : BALL;                 // the press decides: draw or erase
        was = fire;
        SCREEN[p] = fire ? pen : c;
        if (KEYS) {
            KEYS = 0;                                       // drop other keys so they don't pile up
            if (*(volatile char *)0x0277 == 'Q')
                return 0;
        }
        if (wait)
            wait--;
        else if (j & 15) {
            if ((j & 1) && y > 0) y--;
            if ((j & 2) && y < 24) y++;
            if ((j & 4) && x > 0) x--;
            if ((j & 8) && x < 39) x++;
            wait = DELAY;
        }
        SCREEN[y * 40 + x] |= 0x80;
    }
}
