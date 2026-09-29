#
#   Query string / form body parsing and helpers for addon CGIs (MIT, from
#   ccu-addon-mosquitto). Everything here runs on Tcl 8.2 (original CCU3
#   firmware): no dict, no {*}, no eq/ne, no 2>@1, no value-returning
#   regsub or scan.
#
#   The query string parameters listed at the bottom become Tcl variables,
#   URL decoded. A POST body in application/x-www-form-urlencoded form is
#   read with [read_form arr] into an array.
#

# run <cmd> <arg>...: exec with stderr merged into the result (Tcl 8.2 has no
# 2>@1). Raises like exec on a non-zero exit code; strip the
# "child process exited abnormally" suffix with regsub when showing it.
proc shell_quote {s} {
    return "'[string map [list "'" "'\''"] $s]'"
}
proc run {args} {
    set cmd ""
    foreach a $args {
        append cmd [shell_quote $a] " "
    }
    return [exec sh -c "$cmd 2>&1"]
}

# character by character on purpose: no [subst] on user input
proc urldecode {str} {
    set str [string map {+ " "} $str]
    set out ""
    set len [string length $str]
    set i 0
    while {$i < $len} {
        set c [string index $str $i]
        if {$c == "%" && [regexp {^[0-9A-Fa-f]{2}$} [string range $str [expr {$i + 1}] [expr {$i + 2}]] hex]} {
            scan $hex %x code
            append out [binary format c $code]
            incr i 3
        } else {
            append out $c
            incr i
        }
    }
    return [encoding convertfrom utf-8 $out]
}

proc parse_pairs {input arrayName} {
    upvar $arrayName arr
    foreach pair [split $input &] {
        if {[regexp {^([^=]*)=(.*)$} $pair dummy name val]} {
            set arr([urldecode $name]) [urldecode $val]
        }
    }
}

# true for a POST: a CGI changes state only on a POST, a GET only shows
# (docs/04-webui.md, "Change state only on a POST")
proc request_is_post {} {
    global env
    if {![info exists env(REQUEST_METHOD)]} {
        return 0
    }
    return [string equal [string toupper $env(REQUEST_METHOD)] "POST"]
}

# the POST body as an array: read_form body -> $body(user), $body(password).
# Reads CONTENT_LENGTH bytes (up to 1 MiB) and only on a POST; anything else
# leaves the array empty, so change fields in the query are never taken.
proc read_form {arrayName} {
    upvar $arrayName arr
    global env
    array set arr {}
    if {![request_is_post]} {
        return
    }
    set len 0
    if {[info exists env(CONTENT_LENGTH)]} {
        set len $env(CONTENT_LENGTH)
    }
    if {![regexp {^[0-9]+$} $len] || $len == 0 || $len > 1048576} {
        return
    }
    fconfigure stdin -translation binary
    set data [read stdin $len]
    parse_pairs $data arr
}

# minimal JSON string quoting for responses
proc json_string {str} {
    set str [string map {\ \\ \" \\\" \n \n \r \r \t \t} $str]
    return "\"$str\""
}

catch {
    array set query {}
    parse_pairs $env(QUERY_STRING) query
    foreach name {sid cmd file force} {
        if {[info exists query($name)]} {
            set $name $query($name)
        }
    }
}
