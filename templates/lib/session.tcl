#
#   CCU session check for addon CGIs (MIT, from RedMatic / ccu-addon-mosquitto).
#   The WebUI opens the addon's pages with ?sid=@xxxxxxxxxx@; every CGI that
#   reads or changes something must validate it through ReGaHSS.
#   Works on Tcl 8.2 (original CCU3 firmware) and 8.6 (OpenCCU).
#
#     source ../lib/querystring.tcl
#     source ../lib/session.tcl
#     if {![info exists sid] || ![check_session $sid]} { puts {error: invalid session}; exit 0 }
#

load tclrega.so

proc check_session sid {
    if {[regexp {@([0-9a-zA-Z]{10})@} $sid all sidnr]} {
        set res [lindex [rega_script "Write(system.GetSessionVarStr('$sidnr'));"] 1]
        if {$res != ""} {
            return 1
        }
    }
    return 0
}
