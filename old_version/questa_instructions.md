# QuestaSim Simulation Instructions - ECE 554 Minilab 1

## 📁 Required Files

Make sure all these files are in your project directory:

| File | Type | Description |
|------|------|-------------|
| `input_mem.mif` | Provided | Memory initialization (matrix A + vector B) |
| `memory.v` | Provided | Avalon MM memory wrapper |
| `rom.v` | Provided | Quartus ROM IP |
| `rom.qip` | Provided | Quartus IP settings |
| `fifo.sv` | Your code | FIFO module |
| `mac.sv` | Your code | MAC unit with propagation |
| `data_fetcher.sv` | Your code | Avalon MM master |
| `matvec_top.sv` | Your code | Top level module |
| `matvec_tb.sv` | Your code | Testbench |

---

## 🚀 Step-by-Step Instructions

### Step 1: Open QuestaSim

Launch QuestaSim from the Start Menu or via command line.

### Step 2: Navigate to Project Directory

In QuestaSim's Transcript window:
```tcl
cd {C:/Users/Kushal Agrawal/UW-madison school work/SP26/ECE554/minilab_1_contd}
```

> **Note:** Use curly braces `{}` around paths with spaces!

### Step 3: Create Work Library

```tcl
vlib work
vmap work work
```

### Step 4: Compile All Files

Compile in dependency order:
```tcl
vlog rom.v
vlog memory.v
vlog fifo.sv
vlog mac.sv
vlog data_fetcher.sv
vlog matvec_top.sv
vlog matvec_tb.sv
```

Or compile all at once:
```tcl
vlog rom.v memory.v fifo.sv mac.sv data_fetcher.sv matvec_top.sv matvec_tb.sv
```

### Step 5: Run Simulation

```tcl
vsim work.matvec_tb -L C:/intelFPGA_lite/21.1/questa_fse/intel/verilog/altera_mf -voptargs="+acc"
```

> **What this does:**
> - `work.matvec_tb` - Loads our testbench
> - `-L ...altera_mf` - Links Altera memory function library (needed for ROM IP)
> - `-voptargs="+acc"` - Enables full signal visibility for debugging

### Step 6: Run the Test

```tcl
run -all
```

---

## ✅ Expected Output

If everything works correctly, you should see:

```
############################################################
#                                                          #
#      MATRIX-VECTOR MULTIPLICATION TESTBENCH              #
#                ECE 554 - Minilab 1                       #
#                                                          #
############################################################

============================================================
  Initializing Test Data from input_mem.mif
============================================================
Matrix A (8x8):
  Row 0: 01 02 03 04 05 06 07 08
  Row 1: 11 12 13 14 15 16 17 18
  ...

Calculating Expected Results (C = A × B):
  C[0] = 0x0012CC (decimal: 4812)
  C[1] = 0x00550C (decimal: 21772)
  ...

[State transitions and memory reads...]

============================================================
  VERIFICATION RESULTS
============================================================
  C[0]: PASS - Expected=0x0012CC, Got=0x0012CC
  C[1]: PASS - Expected=0x00550C, Got=0x00550C
  C[2]: PASS - Expected=0x00974C, Got=0x00974C
  C[3]: PASS - Expected=0x00D98C, Got=0x00D98C
  C[4]: PASS - Expected=0x011BCC, Got=0x011BCC
  C[5]: PASS - Expected=0x015E0C, Got=0x015E0C
  C[6]: PASS - Expected=0x01A04C, Got=0x01A04C
  C[7]: PASS - Expected=0x01E28C, Got=0x01E28C
------------------------------------------------------------
  ****************************************************
  *              ALL TESTS PASSED!                   *
  *         Matrix-Vector Multiplication OK          *
  ****************************************************
============================================================
```

---

## 🔍 Viewing Waveforms

After running, to see waveforms:

1. In QuestaSim menu: **View → Wave**
2. Add signals:
   ```tcl
   add wave -position insertpoint sim:/matvec_tb/DUT/*
   ```
3. Re-run simulation:
   ```tcl
   restart -f
   run -all
   ```

---

## 🐛 Troubleshooting

### Error: "Cannot find module"
- Make sure all files are compiled
- Check for typos in filenames

### Error: "Cannot find altera_mf"
- Check the library path matches your Quartus installation
- Try: `C:/intelFPGA_lite/23.1std/questa_fse/intel/verilog/altera_mf`

### Error: "Cannot open MIF file"
- Make sure `input_mem.mif` is in the same directory
- Check QuestaSim's current directory with `pwd`

### Simulation hangs (timeout)
- Check state machine transitions
- Add debug prints or check waveforms

### Results are wrong (X's or incorrect values)
- Check FIFO read/write timing
- Verify MAC enable chain
- Check data parsing byte order

---

## 📋 Quick Reference - All Commands

```tcl
# Navigate to project
cd {C:/Users/Kushal Agrawal/UW-madison school work/SP26/ECE554/minilab_1_contd}

# Setup
vlib work
vmap work work

# Compile
vlog rom.v memory.v fifo.sv mac.sv data_fetcher.sv matvec_top.sv matvec_tb.sv

# Run simulation
vsim work.matvec_tb -L C:/intelFPGA_lite/21.1/questa_fse/intel/verilog/altera_mf -voptargs="+acc"

# Execute
run -all

# Optional: View waves
add wave -position insertpoint sim:/matvec_tb/DUT/*
restart -f
run -all
```

---

## 📸 For Your Report

Remember to capture:
1. **Waveform screenshot** showing the full operation
2. **Console output** showing PASS results
3. **Timing of state transitions** (IDLE → FETCH → COMPUTE → DONE)

Good luck! 🎯
