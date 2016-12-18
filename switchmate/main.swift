//
//  main.swift
//  switchmate
//
//  Created by Scott Goldman on 12/16/16.
//  Copyright © 2016 Scott Goldman. All rights reserved.
//

import Foundation

func usageAndExit() {
    print("switchmate tool")
    print("")
    print("commands:")
    print(" discover :                return the first switch device that was discovered")
    print(" discover wait 30 :        wait 30 seconds or to discover the first device,")
    print("                           whichever takes longer")
    print(" getauthkey <device uuid>: go through the pairing process and get an auth key")
    print(" toggle [on/off] <uuid> <key>: toggle the switch")
    exit(1)
}

if CommandLine.argc < 2 {
    usageAndExit()
}

let bt = Bluetooth()

let cmd = CommandLine.arguments[1]
switch cmd {
    case "discover":
        if CommandLine.argc >= 4 {
            switch CommandLine.arguments[2] {
                case "wait":
                    let num = Int(CommandLine.arguments[3])
                    if let seconds = num {
                        bt.scan(seconds)
                    } else {
                        usageAndExit()
                    }
                break
                default:
                    usageAndExit()
            }
        } else if CommandLine.argc == 2 {
            bt.scan()
        } else {
            usageAndExit()
        }
    case "getauthkey":
        if CommandLine.argc == 3 {
            bt.auth(CommandLine.arguments[2])
        } else {
            usageAndExit()
        }
        break

    case "toggle":
        if CommandLine.argc == 5 {
            let on = CommandLine.arguments[2] == "on"
            bt.toggle(on, uuid: CommandLine.arguments[3], authKey: CommandLine.arguments[4])
        } else {
            usageAndExit()
        }
        break
    
    default:
        usageAndExit()
}

dispatchMain()
