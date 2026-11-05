import contextlib
import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('selection',Path(__file__).parents[1]/'run/clean/aux/cleanup_selection.py')
selection=importlib.util.module_from_spec(spec);spec.loader.exec_module(selection)

class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.inventory={'workspace':'DEMO','apps':[{'id':111,'name':'Training Hub'}],'pages':[{'id':0,'name':'Global'},{'id':200,'name':'Certifications'},{'id':201,'name':'Edit Certification'}]}
    def choose(self,kind='app',**kw):
        with contextlib.redirect_stderr(io.StringIO()): return selection.select(self.inventory,kind,**kw)
    def test_known_app(self): self.assertEqual(self.choose(selected='111',yes=True),'111')
    def test_pages(self): self.assertEqual(self.choose('page',selected='200,201,200'),'200,201')
    def test_skip(self): self.assertEqual(self.choose(skip=True,yes=True),'SKIP')
    def test_empty(self):
        self.inventory['apps']=[]
        self.assertEqual(self.choose(yes=True),'SKIP')
    def test_no_guess(self):
        with self.assertRaises(ValueError): self.choose(yes=True)
    def test_outside(self):
        with self.assertRaises(ValueError): self.choose(selected='110')
    def test_global_page(self):
        with self.assertRaises(ValueError): self.choose('page',selected='0')
    def test_conflicting(self):
        with self.assertRaises(ValueError): self.choose(selected='111',skip=True)
    def test_enter_skips(self):
        with patch('sys.stdin',io.StringIO('\n')) as stream:
            stream.isatty=lambda:True
            self.assertEqual(self.choose(),'SKIP')
    def test_noninteractive(self):
        with patch('sys.stdin',io.StringIO('111\n')):
            with self.assertRaises(ValueError): self.choose()
