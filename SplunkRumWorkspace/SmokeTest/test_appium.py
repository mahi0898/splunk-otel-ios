import unittest
import os
import sys
from appium import webdriver
from selenium import webdriver
from time import sleep
import argparse
import subprocess
import json
from random import choice, randint
from datetime import datetime
from selenium.webdriver.common.touch_actions import TouchActions

class HybridIOSTests(unittest.TestCase):

    # set up appium
    def setUp(self):
        print('Printing.....')
        currentDate = datetime.now().strftime('%Y-%m-%d')
        currentTime = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        caps = {}
        
        caps['platformName'] = 'iOS'
        caps['appium:app'] = 'storage:filename=SmokeTest.zip' # The filename of the mobile app
        caps['appium:deviceName'] = sys.argv[2]
        caps['appium:platformVersion'] = sys.argv[1]
        caps['sauce:options'] = {}
        caps['sauce:options']['appiumVersion'] = '1.22.3'
        caps['sauce:options']['build'] = 'Platform Configurator Build ' + currentDate
        caps['sauce:options']['name'] = 'Platform Configurator Job ' + currentTime
        
        url = 'https://sso-splunk.saucelabs.com-mahimag:274c9a94-86d1-4b12-9594-57307cfb2c57@ondemand.us-west-1.saucelabs.com:443/wd/hub'
        self.driver=webdriver.Remote(url,caps)
    

    def tearDown(self):
        sleep(1)
        self.driver.quit()

    #Loads every element in the current view
    def load(self):
        find_next = self.driver.find_element_by_xpath("//*")
        return
            
    #Click on Configure disableMemoryWarning and Test disableMemoryWarning
    def test_API_DisableMemoryWarning(self):
        self.driver.find_element_by_id("CLICK ME").click();

if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromTestCase(HybridIOSTests)
    testRunner_result = unittest.TextTestRunner(verbosity=2).run(suite)
    
    if testRunner_result.wasSuccessful():
        exit(0)
    else:
        exit(1) 
