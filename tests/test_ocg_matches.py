"""Pure protocol/provenance tests; these do not load a native DLL."""
import ctypes as C
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ocg_matches',ROOT/'tools/run_ocg_matches.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class MatchHarnessTests(unittest.TestCase):
    def test_frame_sequence_preserves_message_and_payload(self):
        data=b'\x03\0\0\0\x05\x01\x01'+b'\x02\0\0\0\x28\x00'
        self.assertEqual(list(m.packets(data)),[(5,b'\1\1'),(40,b'\0')])
    def test_frame_rejects_zero_truncated_and_overrun(self):
        for data in (b'\0',b'\0\0\0\0',b'\3\0\0\0\5\1'):
            with self.subTest(data=data),self.assertRaises(ValueError): list(m.packets(data))
    def test_deck_keeps_sections_and_duplicate_card_instances(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'a.ydk';p.write_text('#main\n'+''.join(str(i//3+1)+'\n' for i in range(40))+'#extra\n44\n!side\n55\n')
            d=m.parse_deck(p);self.assertEqual(len(d['main']),40);self.assertEqual(d['main'][:3],[1,1,1]);self.assertEqual(d['extra'],[44]);self.assertEqual(d['side'],[55])
    def test_deck_rejects_wrong_size_and_nondecimal_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'a.ydk'
            for data in ('#main\n1\n','#main\n-1\n','#main\n1x\n'):
                p.write_text(data)
                with self.subTest(data=data),self.assertRaises(ValueError):m.parse_deck(p)
    def card(self,alias=0,kind=17):
        sets=(C.c_uint16*2)(0x1234,0)
        return m.Card(100,alias,sets,kind,4,1,1,1000,1000,0,0,0)
    def test_declarable_code_type_and_setcode(self):
        c=self.card();op=lambda x:x<<32
        self.assertTrue(m.declarable(c,[100,op(0x40000100)]))
        self.assertFalse(m.declarable(c,[101,op(0x40000100)]))
        self.assertTrue(m.declarable(c,[16,op(0x40000102)]))
        self.assertTrue(m.declarable(c,[0x1234,op(0x40000101)]))
        self.assertFalse(m.declarable(c,[0x2234,op(0x40000101)]))
    def test_declarable_alias_token_and_division_restrictions(self):
        op=lambda x:x<<32
        self.assertFalse(m.declarable(self.card(alias=123),[1]))
        self.assertTrue(m.declarable(self.card(alias=123),[op(0x40000014),1]))
        self.assertFalse(m.declarable(self.card(kind=0x4001),[1]))
        self.assertTrue(m.declarable(self.card(kind=0x4001),[op(0x40000015),1]))
        self.assertFalse(m.declarable(self.card(),[1,0,op(0x40000003)]))
        self.assertFalse(m.declarable(self.card(),[1,2]))
    def test_python_pin_matches_known_release(self):
        self.assertEqual(m.PYTHON_SHA256,'084b9eb24cb848605c895d05b738fbc2572efc8b4c18c415a824065864a2b853')
        self.assertTrue(m.PYTHON_URL.startswith('https://www.python.org/ftp/python/3.12.10/'))
    def test_scenario_marker_requires_exact_native_hint_and_owner(self):
        payload=m.struct.pack('<BBQ',2,1,9000001)
        self.assertTrue(m.scenario_completed(2,payload,1,9000001))
        for message,data,player,marker in ((5,payload,1,9000001),(2,payload,0,9000001),
                                         (2,payload,1,9000002),(2,payload[:-1],1,9000001),
                                         (2,m.struct.pack('<BBQ',1,1,9000001),1,9000001)):
            with self.subTest(message=message,data=data,player=player,marker=marker):
                self.assertFalse(m.scenario_completed(message,data,player,marker))
    def test_invalid_scenario_rejected_before_native_engine_access(self):
        engine=m.Engine.__new__(m.Engine)
        for kind,player in (('invalid',0),('choices',2),('choices',-1)):
            with self.subTest(kind=kind,player=player),self.assertRaises(ValueError): engine.prompt_scenario(kind,player,1)
        with self.assertRaises(ValueError): engine.prompt_scenario('choices',0,1,suite='effect')
        with self.assertRaises(ValueError): engine.prompt_scenario('fusion_summon',0,1)
        with self.assertRaises(ValueError): engine.prompt_scenario('fusion_summon',0,1,suite='extra-deck')
        with self.assertRaises(ValueError): engine.prompt_scenario('synchro_trigger',0,1,suite='unknown')
        with self.assertRaises(ValueError): engine.prompt_scenario('choices',0,1,suite='ritual-pendulum')
    def test_effective_rules_reject_implicit_mr3_bits_and_wrong_attack_override(self):
        self.assertEqual(m.verify_scenario_rules(m.struct.pack('<I',m.MR5),m.MR5),m.MR5)
        self.assertEqual(m.verify_scenario_rules(m.struct.pack('<I',m.MR5|2),m.MR5|2),m.MR5|2)
        for actual,expected in ((m.MR5|0x1000,m.MR5),(m.MR5|2,m.MR5),(m.MR5,m.MR5|2)):
            with self.subTest(actual=actual,expected=expected),self.assertRaisesRegex(ValueError,'effective duel rules'):
                m.verify_scenario_rules(m.struct.pack('<I',actual),expected)
        with self.assertRaisesRegex(ValueError,'Truncated'): m.verify_scenario_rules(b'\0\0\0',m.MR5)
    def test_native_chain_order_uses_real_one_byte_solving_events(self):
        events=[{'message':72,'payload':[2]},{'message':75,'payload':[1]},{'message':72,'payload':[1]}]
        self.assertEqual(m.require_chain_order(events,[2,1]),[2,1])
        with self.assertRaises(ValueError):m.require_chain_order(list(reversed(events)),[2,1])
        with self.assertRaises(ValueError):m.require_chain_order([{'message':72,'payload':[2,0,0,0]}],[2])
    def summary_bytes(self):
        data=m.struct.pack('<I',m.MR5)
        for player in (0,1):
            data+=m.struct.pack('<I',8000-player*500)
            for location,count in ((4,7),(8,8)):
                for sequence in range(count):
                    if location==4 and sequence==player:
                        data+=m.struct.pack('<BBI',1,1 if player==0 else 8,0)
                    else: data+=b'\0'
            data+=m.struct.pack('<6I',40-player,5+player,2,3,15-player,1)
        return data+m.struct.pack('<I',0)
    def test_field_summary_exposes_counts_and_occupancy_only(self):
        sides=m.public_field_summary(self.summary_bytes())
        self.assertEqual(sides[0],{'lp':8000,'deckCount':40,'handCount':5,'extraCount':15,
                                  'cards':[{'code':0,'location':4,'sequence':0,'position':1}]})
        self.assertEqual(sides[1]['cards'],[{'code':0,'location':4,'sequence':1,'position':8}])
        self.assertEqual(sides[1]['lp'],7500)
        for data in (b'',self.summary_bytes()[:-1],self.summary_bytes()+b'\0'):
            with self.subTest(size=len(data)),self.assertRaises(ValueError):m.public_field_summary(data)
    def visible_card_query(self):
        values={1:100,8:33,16:4,32:0,256:3200,512:-1,0x80000:1}
        data=b''.join(m.struct.pack('<HI',8,flag)+m.struct.pack('<i',value) for flag,value in values.items())
        return data+m.struct.pack('<HIII',12,0x800000,3,133)+m.struct.pack('<HI',4,0x80000000)
    def test_visible_card_query_uses_live_stats_and_redacts_hidden_fields(self):
        occupied={'code':999,'location':4,'sequence':0,'position':1,'futureDraw':12345}
        visible=m.visible_query_card(self.visible_card_query(),occupied)
        self.assertEqual((visible['code'],visible['attack'],visible['defense'],visible['link'],visible['disabled']),(100,3200,-1,3,True))
        self.assertNotIn('futureDraw',visible)
        hidden=m.visible_query_card(b'private unparsed bytes',{**occupied,'position':8})
        self.assertEqual(hidden,{'code':0,'location':4,'sequence':0,'position':8})
        with self.assertRaises(ValueError):m.visible_query_card(self.visible_card_query()[:-1],occupied)
    def test_board_never_queries_hidden_slot_or_private_locations(self):
        engine=m.Engine.__new__(m.Engine);engine.dll=Mock()
        summary=C.create_string_buffer(self.summary_bytes());visible=C.create_string_buffer(self.visible_card_query())
        def field(duel,length):length._obj.value=len(self.summary_bytes());return C.addressof(summary)
        queried=[]
        def query(duel,length,info):
            queried.append((info._obj.con,info._obj.loc,info._obj.seq))
            length._obj.value=len(self.visible_card_query());return C.addressof(visible)
        engine.dll.OCG_DuelQueryField.side_effect=field;engine.dll.OCG_DuelQuery.side_effect=query
        board=engine.board(None,1)
        self.assertEqual(queried,[(0,4,0)])
        self.assertEqual(board['self']['lp'],7500)
        self.assertEqual(board['self']['cards'],[{'code':0,'location':4,'sequence':1,'position':8}])
        self.assertEqual(board['opponent']['cards'][0]['attack'],3200)
    def test_scenario_evidence_requires_real_message_and_canonical_script(self):
        m.require_scenario_evidence({63,74},{50:3,63:1,74:1},{'c24094653.lua'},{'constant.lua','c24094653.lua'})
        with self.assertRaisesRegex(ValueError,'expected messages'):
            m.require_scenario_evidence({63,74},{74:1},{'c24094653.lua'},{'c24094653.lua'})
        with self.assertRaisesRegex(ValueError,'required canonical scripts'):
            m.require_scenario_evidence({63,74},{63:1,74:1},{'c24094653.lua'},{'constant.lua'})
    def test_negated_summon_evidence_rejects_success_even_when_required_events_exist(self):
        m.require_scenario_evidence({62,74,100},{62:1,74:1,100:1},forbidden_messages={63})
        with self.assertRaisesRegex(ValueError,'forbidden messages'):
            m.require_scenario_evidence({62,74,100},{62:1,63:1,74:1,100:1},forbidden_messages={63})
    def test_answer_passes_only_declarable_codes_and_selecting_player(self):
        engine=m.Engine.__new__(m.Engine);engine.cards={100:self.card(),101:self.card(alias=100)}
        engine.board=Mock(return_value={'self':{'cards':[{'location':4,'sequence':0,'position':1}]},'opponent':{'cards':[]}});node=Mock()
        node.call.return_value={'handled':True,'response':[100,0,0,0]}
        payload=b'\1\2'+m.struct.pack('<QQ',100,0x40000100<<32)
        self.assertEqual(engine.answer(node,'duel',142,payload),b'd\0\0\0')
        self.assertEqual(node.call.call_args.kwargs['declarable'],[100])
        self.assertEqual(node.call.call_args.kwargs['botID'],1)
        engine.board.assert_called_once_with('duel',1)
        self.assertEqual(node.call.call_args.kwargs['ownPositions'],{'0':1})
        self.assertEqual(node.call.call_args.kwargs['board'],engine.board.return_value)
    def test_answer_rejects_invalid_player_and_truncated_announcement(self):
        engine=m.Engine.__new__(m.Engine);node=Mock()
        for message,payload in ((13,b''),(13,b'\2'),(142,b'\0'),(142,b'\0\1')):
            with self.subTest(message=message,payload=payload),self.assertRaises(ValueError): engine.answer(node,None,message,payload)
        node.call.assert_not_called()
    def test_answer_requires_handled_nonempty_bounded_response(self):
        engine=m.Engine.__new__(m.Engine);engine.board=Mock(return_value={'self':{'cards':[]},'opponent':{'cards':[]}});node=Mock()
        for result in ({'handled':False,'response':[1]}, {'handled':True,'response':[]},
                       {'handled':True,'response':[0]*65537}):
            node.call.return_value=result
            with self.subTest(handled=result['handled'],length=len(result['response'])),self.assertRaises(ValueError):
                engine.answer(node,None,13,b'\0')

if __name__=='__main__':unittest.main()
