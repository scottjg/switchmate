//
//  Bluetooth.swift
//  switchmate
//
//  Created by Scott Goldman on 12/16/16.
//  Copyright © 2016 Scott Goldman. All rights reserved.
//

import Cocoa
import CoreBluetooth

class Bluetooth: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var switchmatePeripheral: CBPeripheral?
    var switchmateService: CBService?
    //var switchmateAuthCharacteristic: CBCharacteristic?

    var scanEndTime : time_t = 0

    let SwitchmateServiceUUID = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")
    let SwitchmateAuthCharacteristicUUID = CBUUID(string: "00001529-1212-efde-1523-785feabcd123")
    let SwitchmateStateCharacteristicUUID = CBUUID(string: "00001526-1212-efde-1523-785feabcd123")

    var desiredCharacteristicUUID : CBUUID = CBUUID(string: "00000000-0000-0000-0000-000000000000") //just a default value
    var authKey = Data()
    var desiredSwitchPosition = false

    enum CmdState {
        case None
        case Discover
        case Auth
        case Toggle
    }
    var state = CmdState.None

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        //print("state: \(central.state)")
        //XXX need to verify that the thingee is powered on?
    }
    
    
    // methods to discover the device
    func scan(_ waitTime: time_t = 0) {
        if (waitTime > 0) {
            scanEndTime = time(nil) + waitTime
        }
        fputs("Scanning for peripherals...\n", stderr)
        self.state = CmdState.Discover
        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: [SwitchmateServiceUUID], options: nil)

    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        let name = peripheral.name != nil ? peripheral.name! : "nil"
        let uuid = peripheral.identifier.uuidString
        print("\(uuid) \(RSSI) \(name)")
        
        let now = time(nil)
        if scanEndTime <= now {
            central.stopScan()
            exit(0)
        } else {
            let timeToWait = scanEndTime - now
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeToWait)) {
                central.stopScan()
                exit(0)
            }
        }
    }


    func setupTimeout(timeout: time_t) {
        if (timeout > 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeout)) {
                fputs("Timed out!\n", stderr)
                exit(1)
            }
        }
    }
    
    // get an auth key from the device
    func auth(_ uuid: String, waitTime: time_t = 30) {
        setupTimeout(timeout: waitTime)
        self.state = CmdState.Auth
        desiredCharacteristicUUID = SwitchmateAuthCharacteristicUUID
        setupDeviceConnection(uuid)
    }
    
    //toggle the switch
    func toggle(_ on: Bool, uuid: String, authKey: String, waitTime: time_t = 30) {
        setupTimeout(timeout: waitTime)
        guard let authKeyData = Data(base64Encoded: authKey) else {
            fputs("Auth key is invalid!\n", stderr)
            exit(1)
        }
        self.state = CmdState.Toggle
        self.authKey = authKeyData
        self.desiredSwitchPosition = on
        self.desiredCharacteristicUUID = SwitchmateStateCharacteristicUUID
        setupDeviceConnection(uuid)
        
    }

    //create the connection to the device and handles to the services/characteristics
    func setupDeviceConnection(_ uuid: String) {
        guard let deviceUuid = UUID(uuidString: uuid) else {
            usageAndExit();
            return
        }
        
        fputs("Connecting to device...\n", stderr)
        centralManager.stopScan()
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceUuid])
        guard let peripheral = peripherals.first else {
            fputs("Error retreiving device\n", stderr)
            exit(1)
        }
        self.switchmatePeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    //callback when we have the peripheral, asks to discover services...
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        fputs("Connected to Switchmate \(peripheral.identifier.uuidString), discovering services...\n", stderr)
        peripheral.delegate = self
        peripheral.discoverServices([SwitchmateServiceUUID])
    }
    
    //callback when we have the services, asks to discover characteristics...
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices: Error?) {
        if let error = didDiscoverServices {
            fputs("Failed to get service: \(error)\n", stderr)
            exit(1)
        }
        if let services = peripheral.services {
            if services.count > 0 {
                self.switchmateService = services.first
            }
        }
        
        if let service = self.switchmateService {
            fputs("Discovering characteristics...\n", stderr)
            peripheral.discoverCharacteristics([desiredCharacteristicUUID], for: service)
        } else {
            fputs("Failed to get a service\n", stderr)
            exit(1)
        }
    }
    
    //callback when we have the characteristics, registers for notifications,
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        fputs("Got characteristics, Requesting subscription...\n", stderr)
        if let error = error {
            fputs("Failed to get characteristic: \(error)\n", stderr)
            exit(1)
        }
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                let uuid = characteristic.uuid.uuidString
                switch uuid {
                case SwitchmateAuthCharacteristicUUID.uuidString:
                    //first subscribe for a response from the characteristic, we'll start the
                    //request when that's done.
                    peripheral.setNotifyValue(true, for: characteristic)
                    break
                case SwitchmateStateCharacteristicUUID.uuidString:
                    //first subscribe for a response from the characteristic, we'll start the
                    //request when that's done.
                    peripheral.setNotifyValue(true, for: characteristic)
                    break
                    
                default:
                    //print("got unused characteristic: \(uuid)")
                    break
                }
            }
        }
        
    }
    
    //get acknoweldgement from subscription
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        if let error = error {
            fputs("Failed to subscribe to characteristic: \(error)\n", stderr)
            exit(1)
        }

        fputs("Got subscription, writing command...\n", stderr)
        switch characteristic.uuid.uuidString {
        case SwitchmateAuthCharacteristicUUID.uuidString:
            //send the command to request an auth key
            peripheral.writeValue(Data(bytes: [0,0,0,0,1]), for: characteristic, type: CBCharacteristicWriteType.withResponse)
            break

        case SwitchmateStateCharacteristicUUID.uuidString:
            //send the command to toggle the switch
            var cmd = Data(bytes: [
                0x01,
                self.desiredSwitchPosition ? 0x01 : 0x00
                ])
            let signedCmd = signCmd(&cmd, keyLen: self.authKey.count)
            peripheral.writeValue(signedCmd, for: characteristic, type: CBCharacteristicWriteType.withResponse)
            break
            
        default:
            print("got subscription for unused characteristic: \(characteristic.uuid.uuidString)")
            break
        }
    }

    //callback when the write completed ok, then we wait for an update from the device...
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            fputs("Failed to write to characteristic: \(error)\n", stderr)
            exit(1)
        } else {
            print("Acknowledged successful write!")
        }
        
        switch characteristic.uuid.uuidString {
        case SwitchmateAuthCharacteristicUUID.uuidString:
            fputs("The device is ready to pair, press the button on the switchmate.\n", stderr)
            break
        
            
        case SwitchmateStateCharacteristicUUID.uuidString:
            break

        default:
            //print("got unused characteristic write: \(characteristic.uuid.uuidString)")
            break
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        switch characteristic.uuid.uuidString {
        case SwitchmateAuthCharacteristicUUID.uuidString:
            if let value = characteristic.value {
                if value.count > 3 && value.starts(with: [0x20, 0x01, 0x00]) {
                    let v = value.subdata(in: 3..<value.count)
                    print("\(v.base64EncodedString())")
                    exit(0)
                } else {
                    fputs("Failed to get an auth key. Did you press the button in time?\n", stderr)
                    exit(1)
                }
            }
            break
        case SwitchmateStateCharacteristicUUID.uuidString:
            if let value = characteristic.value {
                if value[2] == 0x00 {
                    fputs("Toggled Ok!\n", stderr)
                    exit(0)
                } else {
                    fputs("Toggled failed with code: \(value[4])!\n", stderr)
                    exit(1)
                }
            }
            break
        default:
            //print("got unused characteristic: \(uuid)")
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fputs("Failed to connect to device\n", stderr)
        exit(1)
    }
    
    func signCmd(_ cmd: inout Data, keyLen: Int) -> Data {
        var blob = Data()
        blob.append(cmd)
        blob.append(self.authKey)
        
        var i: Int = 0
        var x: Int = Int(blob[0]) << 7
        
        while (i < blob.count) {
            let (x1, _) = Int.multiplyWithOverflow(1000003, x)
            x = (x1 ^ (Int(blob[i]) & 0xff)) ^ blob.count
            i += 1
        }
        if (x == -1) {
            x = -2;
        }
        
        var lesig = x.littleEndian
        var sigbytes = Data()
        withUnsafePointer(to: &lesig) {
            sigbytes.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: 4)
        }
        sigbytes.append(cmd)
        
        return sigbytes
    }
}
