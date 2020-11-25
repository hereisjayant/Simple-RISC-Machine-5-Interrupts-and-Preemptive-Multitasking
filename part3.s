
COUNTER:
        .word 0
CHAR_BUFFER:
        .word 0
CHAR_FLAG:
        .word 0
//This code has beeen taken from interrupt_example.s

.include    "address_map_arm.s"
.include    "interrupt_ID.s"

/* ********************************************************************************
 * This program demonstrates use of interrupts with assembly language code.
 * The program responds to interrupts from the pushbutton KEY port in the FPGA.
 *
 * The interrupt service routine for the pushbutton KEYs indicates which KEY has
 * been pressed on the LED display.
 ********************************************************************************/

.section    .vectors, "ax"

            B       _start                  // reset vector
            B       SERVICE_UND             // undefined instruction vector
            B       SERVICE_SVC             // software interrrupt vector
            B       SERVICE_ABT_INST        // aborted prefetch vector
            B       SERVICE_ABT_DATA        // aborted data vector
.word       0 // unused vector

            B       SERVICE_IRQ             // IRQ interrupt vector
            B       SERVICE_FIQ             // FIQ interrupt vector

.text
.global     _start
_start:
/* Set up stack pointers for IRQ and SVC processor modes */
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            LDR     SP, =A9_ONCHIP_END - 3  // set IRQ stack to top of A9 onchip memory
/* Change to SVC (supervisor) mode with interrupts disabled */
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            LDR     SP, =DDR_END - 3        // set SVC stack to top of DDR3 memory

            BL      CONFIG_GIC              // configure the ARM generic interrupt controller

                                            // write to the pushbutton KEY interrupt mask register
            LDR     R0, =KEY_BASE           // pushbutton KEY base address
            MOV     R1, #0xF               // set interrupt mask bits
            STR     R1, [R0, #0x8]          // interrupt mask register is (base + 8)

                                            // enable IRQ interrupts in the processor
            MOV     R0, #0b01010011         // IRQ unmasked, MODE = SVC
            MSR     CPSR_c, R0

            LDR     R0, =MPCORE_PRIV_TIMER // base address of the timer
            LDR     R1, =100000000        //This is the load value => 100000000/200MHZ = .5 second
            STR     R1, [R0]              //Writes to the Load of the TIMER
            MOV     R3, #0b111
            STR     R3, [R0, #0x8]



CONT:
            BL GET_JTAG // read from the JTAG UART
            CMP R0, #0 // check if a character was read
            BEQ CONT
            BL PUT_JTAG
            B  CONT

PUT_JTAG:
            LDR     R1, =JTAG_UART_BASE // JTAG UART base address
            LDR     R2, [R1, #4] // read the JTAG UART control register
            LDR     R3, =0xFFFF
            ANDS    R2, R2, R3 // check for write space
            BEQ   END_PUT // if no space, ignore the character
            STR     R0, [R1] // send the character

END_PUT:
            BX LR

.global GET_JTAG
/**
* Code Taken from Altera Corporation- University Program
* Subroutine to get a character from the JTAG UART
* Returns the character read in R0
*/
GET_JTAG:
            LDR     R1, =JTAG_UART_BASE // JTAG UART base address
            LDR     R0, [R1] // read the JTAG UART data register
            ANDS    R2, R0, #0x8000 // check if there is new data
            BEQ  RET_NULL // if no data, return 0
            AND     R0, R0, #0x00FF // return the character
            B    END_GET

RET_NULL:
            MOV R0, #0
END_GET:
            BX LR

IDLE:
            LDR   R7,=CHAR_FLAG
            LDR   R0,[R7]
            CMP   R0, #1
            BEQ   CF_1
            B       IDLE                    // main program simply idles

CF_1:
            LDR   R1,=CHAR_BUFFER
            LDR   R0,[R1]
            BL    PUT_JTAG
            MOV   R2, #0
            STR   R2, [R7]
            B     IDLE



/* Define the exception service routines */

/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
            B       SERVICE_UND

/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
            B       SERVICE_SVC

/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
            B       SERVICE_ABT_DATA

/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
            B       SERVICE_ABT_INST

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
            PUSH    {R0-R7, LR}

/* Read the ICCIAR from the CPU interface */
            LDR     R4, =MPCORE_GIC_CPUIF
            LDR     R5, [R4, #ICCIAR]       // read from ICCIAR

            CMP     R5, #KEYS_IRQ           //If the R5 is equal to the KEYS_IQR, then
            BEQ      FPGA_IRQ1_HANDLER

//This is for the JTAG_UART Interrupt:
            LDR   R0, =JTAG_UART_BASE    //R0 stores the base of JTAG
            LDRB  R1,[R0]                //Gets the value on JTAG in R1
            LDR   R2,=CHAR_BUFFER
            LDR   R3,=CHAR_FLAG
            STR   R1, [R2]
            MOV   R0, #1
            STR   R0,[R3]

//The following is for The Timer interrupt part 2
            LDR     R0, =LED_BASE           //THis gets the base of the LEDS
            LDR     R1, =COUNTER            //THis get the COUNTER
            LDR     R2, [R1]                 //Gets the current value of the  counter
            ADD     R2, R2, #1              //Adds one to the current value of the counter
            STR     R2, [R0]               //updates the counter on the timer
            STR     R2, [R1]               //updates the counter in the program
            B       EXIT_IRQ


FPGA_IRQ1_HANDLER:
            CMP     R5, #KEYS_IRQ
UNEXPECTED: BNE     UNEXPECTED              // if not recognized, stop here

            BL      KEY_ISR
EXIT_IRQ:
/* Write to the End of Interrupt Register (ICCEOIR) */
            STR     R5, [R4, #ICCEOIR]      // write to ICCEOIR

            POP     {R0-R7, LR}
            SUBS    PC, LR, #4

/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:
            B       SERVICE_FIQ

.end
