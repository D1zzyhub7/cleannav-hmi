from glob import glob
import os

from setuptools import setup


package_name = 'cleannav_hmi_gateway'

setup(
    name=package_name,
    version='0.0.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
         ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'),
         glob('launch/*.launch.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='CleanNav Team',
    maintainer_email='1339980053@qq.com',
    description='CleanNav HMI HTTP gateway and status aggregation',
    license='Apache-2.0',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'cleannav_hmi_gateway = '
            'cleannav_hmi_gateway.gateway_node:main',
            'cleannav_status_aggregator = '
            'cleannav_hmi_gateway.status_aggregator:main',
        ],
    },
)
