#!/usr/bin/env python 

import logging
from optparse import OptionParser
from urllib import urlopen
import sys
try:
    import json as json
except ImportError, err:
    import simplejson as json


def main():

    parser = OptionParser(usage='''%prog [OPTIONS]
Output a factory queue configuration using ACTIVE sites from the
specified cloud and activity type.
''')
    parser.add_option("-c",
                       dest="cloud",
                       action="store",
                       default='ALL',
                       type="string",
                       help="name of cloud")
    parser.add_option("-a",
                       dest="activity",
                       default="analysis",
                       action="store",
                       type="choice",
                       choices=['analysis','production'],
                       help="activity filter ('analysis' [default] or 'production')")
    parser.add_option("-k",
                       dest="keyname",
                       default="ce_name",
                       action="store",
                       type="string",
                       help="name of queue key")
    parser.add_option("-q", "--quiet",
                       dest="loglevel",
                       default=logging.WARNING,
                       action="store_const",
                       const=logging.WARNING,
                       help="Set logging level to WARNING [default]")
    parser.add_option("-v", "--info",
                       dest="loglevel",
                       default=logging.WARNING,
                       action="store_const",
                       const=logging.INFO,
                       help="Set logging level to INFO [default WARNING]")

    (options, args) = parser.parse_args()

    logger = logging.getLogger()
    logger.setLevel(options.loglevel)
    fmt = '[APF:%(levelname)s %(asctime)s] %(message)s'
    formatter = logging.Formatter(fmt, '%T')
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)
    logger.handlers = []
    logger.addHandler(handler)


    msg = 'Cloud: %s' % options.cloud.upper()
    logging.info(msg)
    msg = 'Activity: %s' % options.activity
    logging.info(msg)
    url = 'http://atlas-agis-api.cern.ch/request/pandaqueue/query/list/?json&preset=schedconf.all&vo_name=atlas'
    if options.cloud.upper() != 'ALL':
        url += '&cloud=%s' % options.cloud.upper()
    logging.info(url)
    
    handle = urlopen(url)
    d = json.load(handle, 'utf-8')
    handle.close()

    # loop through PandaQueues
    for key in sorted(d):
       try:
           if d[key]['vo_name'] != 'atlas':
               continue
           if d[key]['site_state'] == 'ACTIVE' and d[key]['type'] == options.activity:
               maxrss = d[key]['maxrss']
               print key, 'maxrss:', maxrss
                               

       except KeyError, e:
           print '# Key error: %s' % e
           print

if __name__ == "__main__":
    sys.exit(main())
