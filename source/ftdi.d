import std.math;
import core.stdc.stdint;
import std.algorithm : max;
import core.sys.posix.unistd;

// UM232H development module
enum VENDOR = 0x0403;
enum PRODUCT = 0x6014;

// ADBUS0
enum  PIN_SCK = 0;
// ADBUS1
enum  PIN_MOSI = 1; 
// ADBUS2
enum  PIN_NSS = 2;

enum  OUTPUT_PINMASK = ((1 << PIN_SCK) | (1 << PIN_MOSI) | (1 << PIN_NSS));


struct SynthConfig
{
    bool trigger;

    uint8_t adsr_ai;
    uint8_t adsr_di;
    uint8_t adsr_s;
    uint8_t adsr_ri;

    uint16_t osc_count;

    uint8_t filter_a;
    uint8_t filter_b;

    void setOscillatorHz(uint16_t hz) nothrow @nogc
    {
        this.osc_count = 40000 / (2*hz);
        this.osc_count = max(cast(ushort)1, this.osc_count);
    }

    void setFilterA(uint8_t a)  nothrow @nogc
    {
        this.filter_a = a;
        this.filter_b = 0xff-a;
    }

    void setFilterD(double a) nothrow @nogc
    {
        this.setFilterA(cast(uint8_t)(a * 0xff));
    }

    /**
     * Note: Even for f=fs/2, this will only set the coefficient to
     * 0.83... which is mathematically corrent. If you want to use higher values,
     * Use setFilterD
     */
    void setFilterHz(uint16_t hz) nothrow @nogc
    {
        // https://dsp.stackexchange.com/a/54088
        double f = hz;
        const fs = 40000;
        auto wc = (f / fs) * 2 * PI;
        double y = 1 - cos(wc);
        double val = -y + sqrt(y*y + 2 * y);

        this.setFilterD(val);
    }

    void setADSR(double aMS, double dMS, double s, double rMS) nothrow @nogc
    {
        // One step takes this time (in ms): 3.2ms
        double stepMS = (128.0 / (40000.0)) * 1000;

        size_t aSteps = cast(size_t)(aMS / stepMS);
        aSteps = max(aSteps, 1);
        size_t dSteps = cast(size_t)(dMS / stepMS);
        dSteps = max(dSteps, 1);
        size_t rSteps = cast(size_t)(rMS / stepMS);
        rSteps = max(rSteps, 1);

        size_t aInc = 255 / aSteps;
        aInc = max(aInc, 1);
        int16_t dInc = cast(int16_t)((255 - s * 255) / dSteps);
        dInc = cast(int16_t)(-max(dInc, 1));
        
        int16_t sAbs = cast(int16_t)(255 + dInc * dSteps);
        
        //enforce(sAbs >= 0 && sAbs <= 255);

        int16_t rInc = cast(int16_t)(-max((sAbs / rSteps), 1));


        this.adsr_ai = cast(uint8_t)aInc;
        this.adsr_di = cast(uint8_t)(dInc & 0xff);
        this.adsr_s = cast(uint8_t)sAbs;
        this.adsr_ri = cast(uint8_t)(rInc & 0xff);
    }
}

struct SPIDriver
{
private:
    ftdi_context _ftdi;

    bool setupMPSSE() nothrow @nogc
    {
        // 1 MHz, Disable adaptive and 3 phase clocking, set ADBUS all spi pins as output, nSS initial high
        uint8_t[8] buf = [TCK_DIVISOR, 0x05, 0x00,
            DIS_ADAPTIVE,
            DIS_3_PHASE,
            SET_BITS_LOW, (1 << PIN_NSS), OUTPUT_PINMASK
        ];
        // Write the setup to the chip.
        if (ftdi_write_data(&_ftdi, buf.ptr, buf.length) != buf.length)
            return false;

        return true;
    }

public:
    // FIXME: Allow specifying device
    bool open() nothrow @nogc
    {
        if (ftdi_init(&_ftdi) != 0)
            return false;

        if (ftdi_usb_open(&_ftdi, VENDOR, PRODUCT) != 0)
            return false;

        if (ftdi_usb_reset(&_ftdi) != 0)
            return false;
        if (ftdi_set_interface(&_ftdi, ftdi_interface.INTERFACE_ANY) != 0)
            return false;
        if (ftdi_set_bitmode(&_ftdi, 0, 0) != 0)
            return false;
        if (ftdi_set_bitmode(&_ftdi, 0, ftdi_mpsse_mode.BITMODE_MPSSE) != 0)
            return false;
        if (ftdi_tcioflush(&_ftdi) != 0)
            return false;
        usleep(50000);

        return setupMPSSE();
    }

    bool writeTrigger(bool on) nothrow @nogc
    {
        uint8_t tbit = on ? 0b1 : 0b0;
        uint8_t[12] buf = [
            SET_BITS_LOW, 0x00, OUTPUT_PINMASK, //nSS low
            MPSSE_DO_WRITE | MPSSE_WRITE_NEG | MPSSE_LSB | MPSSE_BITMODE, 0x00, tbit, // Single BIT CMD, 3.4.3
            SET_BITS_LOW, 0, OUTPUT_PINMASK, // Delay
            SET_BITS_LOW, (1 << PIN_NSS), OUTPUT_PINMASK //nSS high
        ];
        if (ftdi_write_data(&_ftdi, buf.ptr, buf.length) != buf.length)
            return false;

        return true;
    }

    bool writeConfig(SynthConfig cfg) nothrow @nogc
    {
        uint8_t tbit = cfg.trigger ? 0b1 : 0b0;

        uint8_t[22] buf = [
            SET_BITS_LOW, 0x00, OUTPUT_PINMASK, //nSS low
            MPSSE_DO_WRITE | MPSSE_WRITE_NEG | MPSSE_LSB | MPSSE_BITMODE, 0x00, tbit, // Single BIT CMD, 3.4.3 (Trigger)
            MPSSE_DO_WRITE | MPSSE_WRITE_NEG | MPSSE_LSB, 0x04, 0x00, cfg.adsr_ai, cfg.adsr_di, cfg.adsr_s, cfg.adsr_ri, (uint8_t)(cfg.osc_count & 0xff), // Write Byte CMD, 3.4.2
            MPSSE_DO_WRITE | MPSSE_WRITE_NEG | MPSSE_LSB | MPSSE_BITMODE, 0x03, (uint8_t)((cfg.osc_count >> 8) & 0x0f), // 4 BIT CMD, 3.4.3 (High bits of OSC)
            MPSSE_DO_WRITE | MPSSE_WRITE_NEG | MPSSE_LSB, 0x01, 0x00, cfg.filter_a, cfg.filter_b // Write Byte CMD, 3.4.2
        ];
        if (ftdi_write_data(&_ftdi, buf.ptr, buf.length) != buf.length)
            return false;

        // To ensure proper reset, nSS must be low for at least 3.125ms
        usleep(3125);

        uint8_t[3] buf2 = [
            SET_BITS_LOW, (1 << PIN_NSS), OUTPUT_PINMASK //nSS high
        ];
        if (ftdi_write_data(&_ftdi, buf2.ptr, buf2.length) != buf2.length)
            return false;

        return true;
    }

    bool close() nothrow @nogc
    {
        ftdi_usb_reset(&_ftdi);
        if (ftdi_usb_close(&_ftdi) != 0)
            return false;

        return true;
    }
}

extern(C):
nothrow:
@nogc:

enum ftdi_chip_type
{
    TYPE_AM=0,
    TYPE_BM=1,
    TYPE_2232C=2,
    TYPE_R=3,
    TYPE_2232H=4,
    TYPE_4232H=5,
    TYPE_232H=6,
    TYPE_230X=7,
}

/** MPSSE bitbang modes */
enum ftdi_mpsse_mode
{
    BITMODE_RESET  = 0x00,    /**< switch off bitbang mode, back to regular serial/FIFO */
    BITMODE_BITBANG= 0x01,    /**< classical asynchronous bitbang mode, introduced with B-type chips */
    BITMODE_MPSSE  = 0x02,    /**< MPSSE mode, available on 2232x chips */
    BITMODE_SYNCBB = 0x04,    /**< synchronous bitbang mode, available on 2232x and R-type chips  */
    BITMODE_MCU    = 0x08,    /**< MCU Host Bus Emulation mode, available on 2232x chips */
    /* CPU-style fifo mode gets set via EEPROM */
    BITMODE_OPTO   = 0x10,    /**< Fast Opto-Isolated Serial Interface Mode, available on 2232x chips  */
    BITMODE_CBUS   = 0x20,    /**< Bitbang on CBUS pins of R-type chips, configure in EEPROM before */
    BITMODE_SYNCFF = 0x40,    /**< Single Channel Synchronous FIFO mode, available on 2232H chips */
    BITMODE_FT1284 = 0x80,    /**< FT1284 mode, available on 232H chips */
}

/** Port interface for chips with multiple interfaces */
enum ftdi_interface
{
    INTERFACE_ANY = 0,
    INTERFACE_A   = 1,
    INTERFACE_B   = 2,
    INTERFACE_C   = 3,
    INTERFACE_D   = 4
}

/** Automatic loading / unloading of kernel modules */
enum ftdi_module_detach_mode
{
    AUTO_DETACH_SIO_MODULE = 0,
    DONT_DETACH_SIO_MODULE = 1,
    AUTO_DETACH_REATACH_SIO_MODULE = 2
}

/* Shifting commands IN MPSSE Mode*/
enum MPSSE_WRITE_NEG = 0x01;   /* Write TDI/DO on negative TCK/SK edge*/
enum MPSSE_BITMODE   = 0x02;   /* Write bits, not bytes */
enum MPSSE_READ_NEG  = 0x04;   /* Sample TDO/DI on negative TCK/SK edge */
enum MPSSE_LSB       = 0x08;   /* LSB first */
enum MPSSE_DO_WRITE  = 0x10;   /* Write TDI/DO */
enum MPSSE_DO_READ   = 0x20;   /* Read TDO/DI */
enum MPSSE_WRITE_TMS = 0x40;   /* Write TMS/CS */

/* FTDI MPSSE commands */
enum SET_BITS_LOW =  0x80;
enum TCK_DIVISOR  =  0x86;
enum DIS_ADAPTIVE  =  0x97;
enum DIS_3_PHASE   =  0x8d;

struct ftdi_context
{
    /* USB specific */
    /** libusb's context */
    void *usb_ctx;
    /** libusb's usb_dev_handle */
    void *usb_dev;
    /** usb read timeout */
    int usb_read_timeout;
    /** usb write timeout */
    int usb_write_timeout;

    /* FTDI specific */
    /** FTDI chip type */
    ftdi_chip_type type;
    /** baudrate */
    int baudrate;
    /** bitbang mode state */
    ubyte bitbang_enabled;
    /** pointer to read buffer for ftdi_read_data */
    ubyte *readbuffer;
    /** read buffer offset */
    uint readbuffer_offset;
    /** number of remaining data in internal read buffer */
    uint readbuffer_remaining;
    /** read buffer chunk size */
    uint readbuffer_chunksize;
    /** write buffer chunk size */
    uint writebuffer_chunksize;
    /** maximum packet size. Needed for filtering modem status bytes every n packets. */
    uint max_packet_size;

    /* FTDI FT2232C requirecments */
    /** FT2232C interface number: 0 or 1 */
    int finterface;   /* 0 or 1 */
    /** FT2232C index number: 1 or 2 */
    int index;       /* 1 or 2 */
    /* Endpoints */
    /** FT2232C end points: 1 or 2 */
    int in_ep;
    int out_ep;      /* 1 or 2 */

    /** Bitbang mode. 1: (default) Normal bitbang mode, 2: FT2232C SPI bitbang mode */
    ubyte bitbang_mode;

    /** Decoded eeprom structure */
    void *eeprom;

    /** String representation of last error */
    const char *error_str;

    /** Defines behavior in case a kernel module is already attached to the device */
    ftdi_module_detach_mode module_detach_mode;
};

int ftdi_init(ftdi_context *ftdi);
int ftdi_usb_open(ftdi_context *ftdi, int vendor, int product);
int ftdi_usb_reset(ftdi_context *ftdi);
int ftdi_set_interface(ftdi_context *ftdi, ftdi_interface finterface);
int ftdi_tcioflush(ftdi_context *ftdi);
int ftdi_usb_close(ftdi_context *ftdi);
int ftdi_write_data(ftdi_context *ftdi, const uint8_t *buf, int size);
int ftdi_set_bitmode(ftdi_context *ftdi, uint8_t bitmask, uint8_t mode);