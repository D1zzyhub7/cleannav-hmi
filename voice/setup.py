from glob import glob
import os

from setuptools import find_packages, setup


package_name = 'cleannav_voice'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
         ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'config'),
         glob('config/*.yaml')),
    ],
    install_requires=['setuptools', 'PyYAML'],
    zip_safe=True,
    maintainer='CleanNav Team',
    maintainer_email='1339980053@qq.com',
    description='CleanNav offline voice intent to TaskCommand bridge',
    license='Apache-2.0',
    extras_require={'test': ['pytest']},
    entry_points={
        'console_scripts': [
            'voice_bridge_node = cleannav_voice.voice_bridge_node:main',
        ],
    },
)
