################################################################################
# sim_aes.tcl : compile + simulate the AES testbench in ModelSim / Questa
#
#   In the transcript :   do sim_aes.tcl
#   Batch mode        :   vsim -c -do "do sim_aes.tcl"
#
# Expected layout (change PROJ_ROOT below if yours is different):
#       <PROJ_ROOT>/rtl/*.vhd      design files
#       <PROJ_ROOT>/tb/tb_aes.vhd  testbench
#       <PROJ_ROOT>/sim/sim_aes.tcl  this script
#
# After the first run you can call   sim_all   again from the transcript to
# recompile everything and restart, or   rr   as a short alias.
################################################################################

# ------------------------------- settings -------------------------------------
if {[info script] ne ""} {
    set SCRIPT_DIR [file dirname [file normalize [info script]]]
} else {
    set SCRIPT_DIR [pwd]
}
set PROJ_ROOT   [file dirname $SCRIPT_DIR]      ;# folder that contains rtl/ and tb/
set RTL_DIR     [file join $PROJ_ROOT rtl]
set TB_DIR      [file join $PROJ_ROOT tb]
set WORK_LIB    work
set TB_TOP      tb_aes
set DUT_PATH    /$TB_TOP/dut                    ;# instance name of the design in the testbench

set VHDL_FLAGS  {-2008}                         ;# {} = simulator default (VHDL-2002)

# Design files, relative to RTL_DIR, IN COMPILE ORDER (package first, then entities that are
# instantiated, then the ones that instantiate them). Example:
#   set RTL_FILES {AESpkg.vhd key_expansion_timing.vhd aes_256_cyph_fast.vhd}
# Leave the list EMPTY to compile every *.vhd of RTL_DIR: the script then finds a working order by
# itself (it retries the files that failed until nothing more compiles).
set RTL_FILES   {}
set RTL_EXCLUDE {}                              ;# file names to skip in the automatic mode, e.g. {old_cipher.vhd}
set TB_FILES    {tb_aes.vhd}

set RUN_TIME    -all                            ;# the testbench stops its own clock when it is finished
set SHOW_WAVES  1                               ;# 0 = no waves (faster)
set LOG_ALL     0                               ;# 1 = log every signal (needed for waves in batch mode)

# ------------------------------- helpers --------------------------------------
proc say {msg} { echo "\[sim_aes\] $msg" }

proc is_batch {} {
    if {[catch {batch_mode} v]} { return 0 }
    return [expr {$v ? 1 : 0}]
}

# compile one file; returns {0 ""} or {1 message}
proc compile_file {f} {
    global VHDL_FLAGS WORK_LIB
    if {[catch {eval vcom $VHDL_FLAGS -work $WORK_LIB -quiet [list $f]} err]} {
        return [list 1 $err]
    }
    return [list 0 ""]
}

# compile in the given order, stop at the first error
proc compile_ordered {files} {
    foreach f $files {
        say "vcom [file tail $f]"
        lassign [compile_file $f] bad msg
        if {$bad} {
            say "COMPILE ERROR in $f"
            say $msg
            return 1
        }
    }
    return 0
}

# compile in any order: retry the failed files until nothing is left or nothing more compiles
proc compile_auto {files} {
    set pending $files
    set pass 1
    while {[llength $pending] > 0} {
        set failed {}
        set errors {}
        set progress 0
        foreach f $pending {
            lassign [compile_file $f] bad msg
            if {$bad} {
                lappend failed $f
                lappend errors "[file tail $f]: $msg"
            } else {
                say "vcom [file tail $f]  (pass $pass)"
                set progress 1
            }
        }
        if {!$progress} {
            say "COMPILE ERROR, these files do not compile (wrong order is ruled out):"
            foreach e $errors { say $e }
            return 1
        }
        set pending $failed
        incr pass
    }
    return 0
}

# add signals to the wave window, skip the ones that do not exist in this design
proc wave_group {name args} {
    foreach s $args {
        if {[catch {add wave -noupdate -group $name -radix hexadecimal $s} err]} {
            say "wave: $s not found, skipped"
        }
    }
}

proc wave_int {name args} {
    foreach s $args {
        if {[catch {add wave -noupdate -group $name -radix unsigned $s} err]} {
            say "wave: $s not found, skipped"
        }
    }
}

proc setup_waves {} {
    global TB_TOP DUT_PATH
    set tb /$TB_TOP

    add wave -noupdate -divider {clock / reset}
    catch {add wave -noupdate $tb/clk}
    catch {add wave -noupdate $tb/rst}

    wave_group "key interface"  $tb/key_valid $tb/key_ready $tb/key_i
    wave_group "data in"        $tb/valid_i $tb/data_i
    wave_group "data out"       $tb/cyph_valid_o $tb/cyph_data_o
    wave_int   "checker"        $tb/phase $tb/n_pushed $tb/n_checked $tb/n_total $tb/n_errors $tb/max_run
    catch {add wave -noupdate -group "checker" $tb/info_mode}
    wave_int   "checker"        $tb/info_x $tb/info_y $tb/info_bad

    # internals of the design, only what exists in the version under test
    wave_group "dut internals"  $DUT_PATH/vld $DUT_PATH/round_key_valid $DUT_PATH/keys_ready
    wave_group "key expansion"  $DUT_PATH/u_key_exp/busy $DUT_PATH/u_key_exp/valid_wait \
                                $DUT_PATH/u_key_exp/round_key_valid $DUT_PATH/u_key_exp/key_exp_done

    configure wave -signalnamewidth 1
    configure wave -timelineunits ns
}

# ------------------------------- main flow ------------------------------------
proc sim_all {} {
    global RTL_DIR TB_DIR WORK_LIB TB_TOP RTL_FILES RTL_EXCLUDE TB_FILES
    global RUN_TIME SHOW_WAVES LOG_ALL

    # a simulation may still be loaded from the previous run
    catch {quit -sim}

    # library
    if {![file exists $WORK_LIB]} {
        vlib $WORK_LIB
    }
    catch {vmap work $WORK_LIB}

    # collect the files
    set rtl {}
    if {[llength $RTL_FILES] > 0} {
        foreach f $RTL_FILES { lappend rtl [file join $RTL_DIR $f] }
        foreach f $rtl {
            if {![file exists $f]} { say "ERROR: $f does not exist"; return 1 }
        }
        say "compiling [llength $rtl] design files in the given order"
        if {[compile_ordered $rtl]} { return 1 }
    } else {
        foreach f [lsort [glob -nocomplain -directory $RTL_DIR *.vhd]] {
            if {[lsearch -exact $RTL_EXCLUDE [file tail $f]] < 0} { lappend rtl $f }
        }
        if {[llength $rtl] == 0} { say "ERROR: no .vhd files found in $RTL_DIR"; return 1 }
        # the package first: every other file uses it
        set first {}
        set others {}
        foreach f $rtl {
            if {[string match -nocase *pkg* [file tail $f]]} { lappend first $f } else { lappend others $f }
        }
        say "compiling [llength $rtl] design files, order found automatically"
        if {[compile_auto [concat $first $others]]} { return 1 }
    }

    set tb {}
    foreach f $TB_FILES { lappend tb [file join $TB_DIR $f] }
    foreach f $tb {
        if {![file exists $f]} { say "ERROR: testbench $f does not exist"; return 1 }
    }
    if {[compile_ordered $tb]} { return 1 }

    # start the simulation
    say "vsim $WORK_LIB.$TB_TOP"
    if {[catch {vsim -t ps -voptargs=+acc $WORK_LIB.$TB_TOP} err]} {
        say "vsim failed: $err"
        return 1
    }

    if {$SHOW_WAVES && ![is_batch]} {
        setup_waves
    }
    if {$LOG_ALL || [is_batch]} {
        catch {log -r /*}
    }

    run $RUN_TIME

    if {$SHOW_WAVES && ![is_batch]} {
        catch {wave zoom full}
    }
    catch {say "finished at $::now"}
    say "look for \"All tests succeeded\" or \"TESTS FAILED\" in the transcript"
    return 0
}

proc rr {} { sim_all }

set rc [sim_all]
if {[is_batch]} {
    quit -f
}
