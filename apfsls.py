# generate xml for autopyfactory SLS reporting
# Peter Love <p.love@lancaster.ac.uk>

import logging
from os.path import getmtime
import sys
import time
from optparse import OptionParser
from XMLdoc import xml_doc

def generateReport():

    id = 'PilotFactory_voatlas60'
    shortname = 'PilotFactory_voatlas60'
    fullname = 'AutoPyFactory monitoring service on voatlas60'

    logtime = getmtime('/opt/panda/autopyfactory/var/factory.log')
    now = time.time()
    age = now - logtime

    if int(age) < 300:
        availability = 100
    elif int(age) < 600:
        availability = 75
    elif int(age) < 1800:
        availability = 25
    else:
        availability = 0

    availabilitydesc = 'Monitor logfile'
    availabilityinfo = 'Log file should be fresh < 300s'
    refreshperiod = 10
    validityduration = 20
    notes = "http://apfmon.lancs.ac.uk/mon/"

    generator=xml_doc()
    generator.set_value('id', id)
    generator.set_value('shortname', shortname)
    generator.set_value('fullname', fullname)
    generator.set_value('availability', availability)
    generator.add_availability_threshold('available', 75)
    generator.add_availability_threshold('affected', 45)
    generator.add_availability_threshold('degraded', 15)
    generator.set_value('availabilitydesc', availabilitydesc)
    generator.set_value('availabilityinfo', availabilityinfo)
    generator.set_value('refreshperiod', refreshperiod)
    generator.set_value('validityduration', validityduration)
    generator.set_value('notes', notes)
    generator.add_data('age', 'Age of log file in seconds', int(age), generator.info['timestamp'])
    generator.add_data('njobs', 'Number of jobs this cycle', 123, generator.info['timestamp'])


    return generator.print_xml()

def main():
    usage = "usage: %prog [options]"
    parser = OptionParser(usage=usage)
    parser.add_option("-q", action="store_true", default=False,
                      help="quiet mode", dest="quiet")
    parser.add_option("-d", action="store_true", default=False,
                      help="debug mode", dest="debug")
    (options, args) = parser.parse_args()
    if len(args) != 0:
        parser.error("incorrect number of arguments")
        return 1
    loglevel = 'INFO'
    if options.quiet:
        loglevel = 'WARNING'
    if options.debug:
        loglevel = 'DEBUG'

    logger = logging.getLogger()
    logger.setLevel(logging._levelNames[loglevel])
    fmt = '[APF:%(levelname)s %(asctime)s] %(message)s'
    formatter = logging.Formatter(fmt, '%T')
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    print generateReport()

if __name__ == "__main__":
    sys.exit(main())

