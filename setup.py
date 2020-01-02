from mypyc.build import mypycify
from setuptools import setup

setup(
    name='nixos-secrets',
    version='0.2',
    description='Encrypted secrets management for NixOS',
    url='http://github.com/lopsided98/nixos-secrets',
    author='Ben Wolsieffer',
    author_email='benwolsieffer@gmail.com',
    license='MIT',

    ext_modules=mypycify(['nixos_secrets.py']),
    entry_points={
        'console_scripts': ['nixos-secrets=nixos_secrets:main'],
    },

    install_requires=['python-gnupg']
)
