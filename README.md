# ccu-addon-howto

> Howto für die Entwicklung von Addons für die Homematic CCU und RaspberryMatic

**WORK IN PROGRESS**

## Inhalt

* [Einführung](#einführung)
* [Struktur eines Addons]()
  * update_script
  * rc_script
  * ...
* [Button in Systemsteuerung]()
* [Update Check]()
* [UI, tcl cgi scripts]()
* [Binaries portieren/bauen]()
* [Individuelle Webserver Konfiguration]()
* [Cronjobs]()
* [Backup-Ausnahmen (RaspberryMatic)]()
* [Monit (RaspberryMatic)]()
* [Dateien in Readonly Partition patchen]()
* [Best Practices]()
  * Buildautomatisierung
  * Continuous Integration mit Travis
  * ...
* ...
* [Lizenz](#lizenz)

## Einführung

_...Erläuterung Buildroot basierte Systeme vs. Paketmanagement a la apt/rpm/..._


## Stuktur eines Addons

Eine Addon Datei ist eine .tar.gz Datei die auf oberster Ebene ein Shellscript `update_script` enthält. Dieses wird
bei der Addon Installation ausgeführt.

Im Folgenden wird ein minimales Addon namens "foobar" beschrieben. 


```
ccu-addon-foobar-1.0.tar.gz
    + foobar
    |- file1
    |- file2 
    |-  ... 
    - update_script
    - rc_script
```


### update_script

```
#!/bin/sh

ADDONS_PATH=/usr/local/addons/
RC_PATH=/usr/local/etc/config/rc.d/

mount | grep /usr/local 2>&1 >/dev/null
if [ $? -eq 1 ]; then
  mount /usr/local
fi

cp -af foobar $ADDONS_PATH
cp -f rc_script $RC_PATH/foobar

sync
exit 0
```

#### Reboot nach Installation steuern (RaspberryMatic)

RaspberryMatic bietet die Möglichkeit über den Exit Code des update_script zu steuern ob ein Addon nach der Installation 
einen Reboot benötigt. Wird das update_script mit `exit 0` verlassen macht RaspberryMatic keinen Reboot, wird ein Reboot 
benötigt kann dies über `exit 10` erzwungen werden. Die CCU3 Firmware bietet dieses Feature nicht, hier wird immer ein
Zwangsreboot nach Verlassen des update_script durchgeführt.

### rc_script

Das rc_script dient dazu Informationen und Buttons in der Systemsteuerung/Zusatzsoftware bereitzustellen sowie (falls
vorhanden) Services des Addons beim Systemstart zu starten.

Commands:
* info
* uninstall
* start (optional)
* stop (optional)
* restart (optional)

```
#!/bin/sh


```


## Button in Systemsteuerung

Zum Anlegen und Entfernen von Buttons im WebUI unter Systemsteuerung ...

## Binaries portieren/bauen

## Individuelle Webserver Konfiguration

## Backup-Ausnahmen (RaspberryMatic)

RaspberryMatic bietet die Möglichkeit Verzeichnisse aus dem Backup auszunehmen. Wird in einem Verzeichnis eine Datei
mit dem Namen `.nobackup` angelegt wird RaspberryMatic dieses Verzeichnis beim Backup nicht sichern. Die CCU3 bietet 
diese Feature (leider, noch?) nicht.

## Dateien in Readonly Partition patchen



## Best Practices

## Lizenz

* [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode.de) (c) [see AUTHORS](AUTHORS)