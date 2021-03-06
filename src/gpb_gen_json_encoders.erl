%%% Copyright (C) 2019  Tomas Abrahamsson
%%%
%%% Author: Tomas Abrahamsson <tab@lysator.liu.se>
%%%
%%% This library is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU Lesser General Public
%%% License as published by the Free Software Foundation; either
%%% version 2.1 of the License, or (at your option) any later version.
%%%
%%% This library is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public
%%% License along with this library; if not, write to the Free Software
%%% Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
%%% MA  02110-1301  USA

%%% @private
%%% @doc Generation of conversion routines from internal format to JSON

-module(gpb_gen_json_encoders).

-export([format_exports/2]).
-export([format_top_function/3]).
-export([format_encoders/3]).

-include("../include/gpb.hrl").
-include("gpb_codegen.hrl").
-include("gpb_compile.hrl").

-import(gpb_lib, [replace_term/2, replace_tree/2,
                  splice_trees/2, repeat_clauses/2]).

format_exports(Defs, Opts) ->
    DoNif = proplists:get_bool(nif, Opts),
    [case gpb_lib:get_records_or_maps_by_opts(Opts) of
         records ->
             ?f("-export([to_json/1, to_json/2, to_json/3]).~n");
         maps ->
             ?f("-export([to_json/2, to_json/3]).~n")
     end,
     [[[begin
            NoWrapperFnName = gpb_lib:mk_fn(to_json_msg_, MsgName),
            if DoNif ->
                    ?f("-export([~p/1]).~n", [NoWrapperFnName]);
               not DoNif ->
                    ?f("-export([~p/1, ~p/2]).~n",
                       [NoWrapperFnName, NoWrapperFnName])
            end
        end
        || {{msg,MsgName}, _Fields} <- Defs],
       "\n"]
      || gpb_lib:get_bypass_wrappers_by_opts(Opts)]].

format_top_function(Defs, AnRes, Opts) ->
    case [Item || {{msg, _}, _}=Item <- Defs] of
        [] ->
            format_top_function_no_msgs(Opts);
        MsgDefs ->
            format_top_function_aux(MsgDefs, AnRes, Opts)
    end.

format_encoders(Defs, AnRes, Opts) ->
    [format_to_json_msgs(Defs, AnRes, Opts),
     format_json_helpers(Defs, AnRes, Opts)].

format_top_function_no_msgs(Opts) ->
    Mapping = gpb_lib:get_records_or_maps_by_opts(Opts),
    [case Mapping of
         records ->
             ["-spec to_json(_) -> no_return().\n",
              gpb_codegen:format_fn(
                to_json,
                fun(Msg) -> call_self(Msg, []) end),
              ?f("-spec to_json(_,_) -> no_return().\n"),
              gpb_codegen:format_fn(
                to_json,
                fun(Msg,Opts) when tuple_size(Msg) >= 1, is_list(Opts)->
                        call_self(Msg, element(1,Msg), Opts);
                   (Msg,MsgName) when tuple_size(Msg) >= 1, is_atom(MsgName)->
                        call_self(Msg, MsgName, [])
                end)];
         maps ->
             [?f("-spec to_json(_,_) -> no_return().\n"),
              gpb_codegen:format_fn(
                to_json,
                fun(Msg,MsgName) when is_map(Msg), is_atom(MsgName)->
                        call_self(Msg, MsgName, [])
                end)]
     end,
     ?f("-spec to_json(_,_,_) -> no_return().\n"),
     gpb_codegen:format_fn(
       to_json,
       fun(_Msg, MsgName, _Opts) ->
               error({gpb_error, {no_such_message, MsgName}})
       end)].

format_top_function_aux(MsgDefs, AnRes, Opts) ->
    Verify = proplists:get_value(verify, Opts, optionally),
    JVerify = proplists:get_value(json_verify, Opts, Verify),
    Mapping = gpb_lib:get_records_or_maps_by_opts(Opts),
    DoNif = proplists:get_bool(nif, Opts),
    [case Mapping of

         records ->
             [gpb_codegen:format_fn(
                to_json,
                fun(Msg) -> call_self(Msg, []) end),
              gpb_codegen:format_fn(
                to_json,
                fun(Msg,Opts) when tuple_size(Msg) >= 1, is_list(Opts)->
                        call_self(Msg, element(1,Msg), Opts);
                   (Msg,MsgName) when tuple_size(Msg) >= 1, is_atom(MsgName)->
                        call_self(Msg, MsgName, [])
                end)];
         maps ->
             [gpb_codegen:format_fn(
                to_json,
                fun(Msg,MsgName) when is_map(Msg), is_atom(MsgName)->
                        call_self(Msg, MsgName, [])
                end)]
     end,
     gpb_codegen:format_fn(
       to_json,
       fun(Msg, MsgName, Opts) ->
               '<possibly-verify-msg>',
               TrUserData = proplists:get_value(user_data, Opts),
               case MsgName of
                   '<msg-name-match>' ->
                       'to_json_Msg'('Tr'(Msg, TrUserData), 'TrUserData');
                   X ->
                       error({gpb_error, {no_such_message, X}})
               end
       end,
       [splice_trees('<possibly-verify-msg>',
                     case JVerify of
                         optionally ->
                             [?expr(case proplists:get_bool(verify, Opts) of
                                        true  -> verify_msg(Msg, MsgName, Opts);
                                        false -> ok
                                    end)];
                         always ->
                             [?expr(verify_msg(Msg, MsgName, Opts))];
                         never ->
                             []
                     end),
       repeat_clauses(
          '<msg-name-match>',
          [begin
               ElemPath = [MsgName],
               Transl = gpb_gen_translators:find_translation(
                          ElemPath, encode, AnRes),
               [replace_term('<msg-name-match>', MsgName),
                replace_term('to_json_Msg', gpb_lib:mk_fn(to_json_msg_,
                                                          MsgName)),
                replace_term('Tr', Transl),
                splice_trees('TrUserData', if DoNif -> [];
                                              true  -> [?expr(TrUserData)]
                                           end)]
           end
           || {{msg,MsgName}, _Fields} <- MsgDefs])])].

format_to_json_msgs(Defs, AnRes, Opts) ->
    [format_to_json_msg(MsgName, MsgDef, Defs, AnRes, Opts)
     || {_Type, MsgName, MsgDef} <- gpb_lib:msgs_or_groups(Defs)].

format_to_json_msg(MsgName, MsgDef, Defs, AnRes, Opts) ->
    case gpb_lib:get_field_names(MsgDef) of
        [] ->
            format_to_json_msg_no_fields(MsgName);
        FNames ->
            format_to_json_msg_aux(MsgName, MsgDef, FNames, Defs, AnRes, Opts)
    end.

format_to_json_msg_no_fields(MsgName) ->
    FnName = gpb_lib:mk_fn(to_json_msg_, MsgName),
    [gpb_codegen:format_fn(
       FnName,
       fun(_Msg, _TrUserData) ->
               tj_finalize_obj(tj_new_object())
       end)].

format_to_json_msg_aux(MsgName, MsgDef, FNames, Defs, AnRes, Opts) ->
    FVars = [gpb_lib:var_f_n(I) || I <- lists:seq(1, length(FNames))],
    JVars = [gpb_lib:var_j_n(I) || I <- lists:seq(1, length(FNames)-1)] ++
        [last],
    MsgVar = ?expr(M),
    TrUserDataVar = ?expr(TrUserData),

    {ToJExprs, _} =
        lists:mapfoldl(
          fun({NewJVar, Field, FVar}, PrevJVar) when NewJVar /= last ->
                  Tr = gpb_gen_translators:mk_find_tr_fn(MsgName, Field, AnRes),
                  EncExpr = field_to_json_expr(MsgName, MsgVar, Field, FVar,
                                               PrevJVar, TrUserDataVar,
                                               Defs, Tr, AnRes, Opts),
                  E = ?expr('NewJ' = '<to-j-expr>',
                            [replace_tree('NewJ', NewJVar),
                             replace_tree('<to-j-expr>', EncExpr)]),
                  {E, NewJVar};
             ({last, Field, FVar}, PrevJVar) ->
                  Tr = gpb_gen_translators:mk_find_tr_fn(MsgName, Field, AnRes),
                  EncExpr = field_to_json_expr(MsgName, MsgVar, Field, FVar,
                                               PrevJVar, TrUserDataVar,
                                               Defs, Tr, AnRes, Opts),
                  FinalExpr = ?expr(tj_finalize_obj('<enc-expr>'),
                                    [replace_tree('<enc-expr>', EncExpr)]),
                  {FinalExpr, dummy}
          end,
          ?expr(J0),
          lists:zip3(JVars, MsgDef, FVars)),
    FnName = gpb_lib:mk_fn(to_json_msg_, MsgName),
    FieldMatching =
        case gpb_lib:get_mapping_and_unset_by_opts(Opts) of
            records ->
                gpb_lib:mapping_match(MsgName, lists:zip(FNames, FVars), Opts);
            #maps{unset_optional=present_undefined} ->
                gpb_lib:mapping_match(MsgName, lists:zip(FNames, FVars), Opts);
            #maps{unset_optional=omitted} ->
                FMap = gpb_lib:zip_for_non_opt_fields(MsgDef, FVars),
                if length(FMap) == length(FNames) ->
                        gpb_lib:map_match(FMap, Opts);
                   length(FMap) < length(FNames) ->
                        ?expr('mapmatch' = 'M',
                              [replace_tree('mapmatch',
                                            gpb_lib:map_match(FMap, Opts)),
                               replace_tree('M', MsgVar)])
                end
        end,
    [[[gpb_codegen:format_fn(
         gpb_lib:mk_fn(to_json_msg_, MsgName),
         fun(Msg) ->
                 %% The undefined is the default TrUserData
                 'to_json_msg_MsgName'(Msg, undefined)
         end,
         [replace_term('to_json_msg_MsgName',
                       gpb_lib:mk_fn(to_json_msg_, MsgName))]),
       "\n"]
      || gpb_lib:get_bypass_wrappers_by_opts(Opts)],
     gpb_codegen:format_fn(
       FnName,
       fun('<msg-matching>', TrUserData) ->
               J0 = tj_new_object(),
               '<to-j-param-exprs>'
       end,
       [replace_tree('<msg-matching>', FieldMatching),
        splice_trees('<to-j-param-exprs>', ToJExprs)])].

field_to_json_expr(MsgName, MsgVar, #?gpb_field{name=FName}=Field,
                   FVar, PrevJVar, TrUserDataVar, Defs, Tr, AnRes, Opts)->
    #?gpb_field{occurrence=Occurrence, type=Type, name=FName}=Field,
    TrFVar = gpb_lib:prefix_var("Tr", FVar),
    FEncoderExpr = fun(Var) -> type_to_json_expr(Var, Field, TrUserDataVar) end,
    JFName = json_field_name(Field, Opts),
    Transforms = [replace_term('fieldname', FName),
                  replace_tree('jfieldname', JFName),
                  replace_tree('F', FVar),
                  replace_tree('TrF', TrFVar),
                  replace_term('Tr', Tr(encode)),
                  replace_tree('TrUserData', TrUserDataVar),
                  replace_tree('Json', PrevJVar)],
    IsEnum = case Type of
                 {enum,_} -> true;
                 _ -> false
             end,
    %% Shoult EmitTypeDefaults be a run-time option?
    %% or alternatively a run-time option?
    EmitTypeDefaults =
        proplists:get_bool(json_always_print_primitive_fields, Opts),

    case Occurrence of
        optional ->
            EncodeExpr =
                case gpb:is_msg_proto3(MsgName, Defs) of
                    false ->
                        ?expr(begin
                                  'TrF' = 'Tr'('F', 'TrUserData'),
                                  tj_add_field(jfieldname, '<enc>', 'Json')
                              end,
                              [replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                               Transforms]);
                    true when EmitTypeDefaults ->
                        ?expr(begin
                                  'TrF' = 'Tr'('F', 'TrUserData'),
                                  tj_add_field(jfieldname, '<enc>', 'Json')
                              end,
                              [replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                               Transforms]);
                    true when Type == string ->
                        ?expr(begin
                                  'TrF' = 'Tr'('F', 'TrUserData'),
                                  case is_empty_string('TrF') of
                                      true ->
                                          'Json';
                                      false ->
                                          tj_add_field(jfieldname, '<enc>',
                                                       'Json')
                                  end
                              end,
                              [replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                               Transforms]);
                    true when Type == bytes ->
                        ?expr(begin
                                  'TrF' = 'Tr'('F', 'TrUserData'),
                                  case iolist_size('TrF') of
                                      0 ->
                                          'Json';
                                      _ ->
                                          tj_add_field(jfieldname, '<enc>',
                                                       'Json')
                                  end
                              end,
                              [replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                               Transforms]);
                    true when IsEnum ->
                        TypeDefault = gpb:proto3_type_default(Type, Defs),
                        ?expr(
                           begin
                               'TrF' = 'Tr'('F', 'TrUserData'),
                               if 'TrF' =:= '<TypeDefault>';
                                  'TrF' =:= 0 ->
                                       'Json';
                                  true ->
                                       tj_add_field(jfieldname, '<enc>',
                                                    'Json')
                               end
                           end,
                           [replace_term('<TypeDefault>', TypeDefault),
                            replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                            Transforms]);
                    true ->
                        TypeDefault = gpb:proto3_type_default(Type, Defs),
                        ?expr(
                           begin
                               'TrF' = 'Tr'('F', 'TrUserData'),
                               if 'TrF' =:= '<TypeDefault>' ->
                                       'Json';
                                  true ->
                                       tj_add_field(jfieldname, '<enc>',
                                                    'Json')
                               end
                           end,
                           [replace_term('<TypeDefault>', TypeDefault),
                            replace_tree('<enc>', FEncoderExpr(TrFVar)) |
                            Transforms])
                end,
            case gpb_lib:get_mapping_and_unset_by_opts(Opts) of
                records ->
                    ?expr(
                       if 'F' == undefined ->
                               'Json';
                          true ->
                               '<encodeit>'
                       end,
                       [replace_tree('<encodeit>', EncodeExpr) | Transforms]);
                #maps{unset_optional=present_undefined} ->
                    ?expr(
                       if 'F' == undefined ->
                               'Json';
                          true ->
                               '<encodeit>'
                       end,
                       [replace_tree('<encodeit>', EncodeExpr) | Transforms]);
                #maps{unset_optional=omitted} ->
                    ?expr(
                       case 'M' of
                           '#{fieldname := <F>}' ->
                               '<encodeit>';
                           _ ->
                               'Json'
                       end,
                       [replace_tree('M', MsgVar),
                        replace_tree('#{fieldname := <F>}',
                                     gpb_lib:map_match([{FName,FVar}], Opts)),
                        replace_tree('<encodeit>', EncodeExpr)
                        | Transforms])
            end;
        repeated ->
            ElemPath = [MsgName, FName, []],
            ElemTransl = gpb_gen_translators:find_translation(
                           ElemPath, encode, AnRes),
            ToJsonExpr =
                case Type of
                    {map, KT, VT} ->
                        [_KField, VField] = gpb:map_item_pseudo_fields(KT, VT),
                        VF = type_to_json_expr(?expr(V), VField, TrUserDataVar),
                        ?expr(tj_mapfield_fold(
                                fun(Elem) -> 'MapElemTr'(Elem, 'TrUserData')
                                end,
                                fun(V) -> '<VF>' end,
                                'Value'),
                              [replace_term('MapElemTr', ElemTransl),
                               replace_tree('<VF>', VF),
                               replace_tree('Value', FEncoderExpr(TrFVar)),
                               replace_tree('TrUserData', TrUserDataVar)]);
                    _ ->
                        ?expr(tj_array(['ElemTr'('<enc>', 'TrUserData')
                                        || Elem <- 'TrF']),
                              [replace_term('ElemTr', ElemTransl),
                               replace_tree('<enc>',
                                            FEncoderExpr(?expr(Elem))) |
                               Transforms])
                end,
            RTransforms = Transforms ++
                [replace_tree('<tojson-repeated>', ToJsonExpr)],
            case gpb_lib:get_mapping_and_unset_by_opts(Opts) of
                records ->
                    ?expr(
                       begin
                           'TrF' = 'Tr'('F', 'TrUserData'),
                           if 'TrF' == [] -> 'Json';
                              true -> tj_add_field(jfieldname,
                                                   '<tojson-repeated>',
                                                   'Json')
                           end
                       end,
                       RTransforms);
                #maps{unset_optional=present_undefined} ->
                    ?expr(
                       begin
                           'TrF' = 'Tr'('F', 'TrUserData'),
                           if 'TrF' == [] -> 'Json';
                              true -> tj_add_field(jfieldname,
                                                   '<tojson-repeated>',
                                                   'Json')
                           end
                       end,
                       RTransforms);
                #maps{unset_optional=omitted} ->
                    ?expr(
                       case 'M' of
                           '#{fieldname := <F>}' ->
                               'TrF' = 'Tr'('F', 'TrUserData'),
                               if 'TrF' == [] -> 'Json';
                                  true -> tj_add_field(jfieldname,
                                                       '<tojson-repeated>',
                                                       'Json')
                               end;
                           _ ->
                               'Json'
                       end,
                       [replace_tree('M', MsgVar),
                        replace_tree('#{fieldname := <F>}',
                                     gpb_lib:map_match([{FName,FVar}], Opts)) |
                        RTransforms])
            end;
        required ->
            ?expr(
               begin
                   'TrF' = 'Tr'('F', 'TrUserData'),
                   tj_add_field(jfieldname, '<encodeit>', 'Json')
               end,
               [replace_tree('<encodeit>', FEncoderExpr(TrFVar)) |
                Transforms])
    end;
field_to_json_expr(MsgName, MsgVar, #gpb_oneof{name=FName, fields=OFields},
                   FVar, PrevJVar, TrUserDataVar, Defs, Tr, AnRes, Opts) ->
    ElemPath = [MsgName, FName],
    Transl = gpb_gen_translators:find_translation(ElemPath, encode, AnRes),
    case gpb_lib:get_mapping_and_unset_by_opts(Opts) of
        records ->
            ?expr(if 'F' =:= undefined -> 'Bin';
                     true -> '<expr>'
                  end,
                  [replace_tree('F', FVar),
                   replace_tree('Bin', PrevJVar),
                   replace_tree('<expr>',
                                field_encode_oneof(
                                  MsgName, MsgVar, FVar, OFields,
                                  Transl, TrUserDataVar, PrevJVar,
                                  Defs, Tr, AnRes, Opts))]);
        #maps{unset_optional=present_undefined} ->
            ?expr(if 'F' =:= undefined -> 'Bin';
                     true -> '<expr>'
                  end,
                  [replace_tree('F', FVar),
                   replace_tree('Bin', PrevJVar),
                   replace_tree('<expr>',
                                field_encode_oneof(
                                  MsgName, MsgVar, FVar, OFields,
                                  Transl, TrUserDataVar, PrevJVar,
                                  Defs, Tr, AnRes, Opts))]);
        #maps{unset_optional=omitted, oneof=tuples} ->
            ?expr(case 'M' of
                      '#{fname:=F}' -> '<expr>';
                      _ -> 'Bin'
                  end,
                  [replace_tree('#{fname:=F}',
                                gpb_lib:map_match([{FName, FVar}], Opts)),
                   replace_tree('M', MsgVar),
                   replace_tree('Bin', PrevJVar),
                   replace_tree('<expr>',
                                field_encode_oneof(
                                  MsgName, MsgVar, FVar, OFields,
                                  Transl, TrUserDataVar, PrevJVar,
                                  Defs, Tr, AnRes, Opts))]);
        #maps{unset_optional=omitted, oneof=flat} ->
            ?expr(case 'M' of
                      '#{tag:=Val}' -> '<expr>';
                      _ -> 'Bin'
                  end,
                  [replace_tree('M', MsgVar),
                   replace_tree('Bin', PrevJVar),
                   repeat_clauses(
                     '#{tag:=Val}',
                     field_encode_oneof_flat(
                       '#{tag:=Val}', MsgName, MsgVar, FVar, OFields,
                       Transl, TrUserDataVar, PrevJVar,
                       Defs, Tr, AnRes, Opts))])
    end.

field_encode_oneof(MsgName, MsgVar, FVar, OFields,
                   Transl, TrUserDataVar, PrevJVar, Defs, Tr, AnRes, Opts) ->
    TVar = gpb_lib:prefix_var("T", FVar),
    ?expr(case 'Tr'('F', 'TrUserData') of
              '{tag,TVar}' -> '<expr>'
          end,
          [replace_term('Tr', Transl),
           replace_tree('TrUserData', TrUserDataVar),
           replace_tree('F', FVar),
           repeat_clauses(
             '{tag,TVar}',
             [begin
                  TagTuple = ?expr({tag,'TVar'}, [replace_term(tag,Name),
                                                  replace_tree('TVar', TVar)]),
                  %% undefined is already handled, we have a match,
                  %% the field occurs, as if it had been required
                  OField2 = OField#?gpb_field{occurrence=required},
                  Tr2 = Tr({update_elem_path,Name}),
                  EncExpr = field_to_json_expr(MsgName, MsgVar, OField2, TVar,
                                               PrevJVar, TrUserDataVar,
                                               Defs, Tr2, AnRes, Opts),
                  [replace_tree('{tag,TVar}', TagTuple),
                   replace_tree('<expr>', EncExpr)]
              end
              || #?gpb_field{name=Name}=OField <- OFields])]).

field_encode_oneof_flat(ClauseMarker, MsgName, MsgVar, FVar, OFields,
                        Transl, TrUserDataVar, PrevJVar, Defs, Tr, AnRes, Opts) ->
    OFVar = gpb_lib:prefix_var("O", FVar),
    [begin
         MatchPattern = gpb_lib:map_match([{Name, OFVar}], Opts),
         %% undefined is already handled, we have a match,
         %% the field occurs, as if it had been required
         OField2 = OField#?gpb_field{occurrence=required},
         Tr2 = Tr({update_elem_path,Name}),
         EncExpr = field_to_json_expr(MsgName, MsgVar, OField2, OFVar,
                                      PrevJVar, TrUserDataVar,
                                      Defs, Tr2, AnRes, Opts),
         TrEncExpr = ?expr('Tr'('EncExpr', 'TrUserData'),
                           [replace_term('Tr', Transl),
                            replace_tree('EncExpr', EncExpr),
                            replace_tree('TrUserData', TrUserDataVar)]),
         [replace_tree(ClauseMarker, MatchPattern),
          replace_tree('<expr>', TrEncExpr)]
     end
     || #?gpb_field{name=Name}=OField <- OFields].

type_to_json_expr(Var, #?gpb_field{type=Type}, TrUserDataVar) ->
    case Type of
        Int32 when Int32 == sint32;
                   Int32 == int32;
                   Int32 == uint32 ->
            Var;
        Int64 when Int64 == sint64;
                   Int64 == int64;
                   Int64 == uint64 ->
            ?expr(tj_string(integer_to_list('Value')),
                  [replace_tree('Value', Var)]);
        bool ->
            Var;
        {enum,_EnumName} ->
            ?expr(if is_integer('Value') -> 'Value';
                     is_atom('Value') -> tj_string(atom_to_list('Value'))
                  end,
                  [replace_tree('Value', Var)]);
        Int32 when Int32 == fixed32;
                   Int32 == sfixed32 ->
            Var;
        Int64 when Int64 == fixed64;
                   Int64 == sfixed64 ->
            ?expr(tj_string(integer_to_list('Value')),
                  [replace_tree('Value', Var)]);
        Float when Float == float;
                   Float == double ->
            ?expr(if is_integer('Value') -> 'Value';
                     is_float('Value') -> tj_float('Value');
                     'Value';
                     'Value' == infinity -> <<"Infinity">>;
                     'Value' == '-infinity' -> <<"-Infinity">>;
                     'Value' == nan -> <<"NaN">>
                  end,
                  [replace_tree('Value', Var)]);
        string ->
            ?expr(tj_string('Value'),
                  [replace_tree('Value', Var)]);
        bytes ->
            %% Need option for "websafe base64 escape with padding"?
            ?expr(tj_bytes('Value'),
                  [replace_tree('Value', Var)]);
        {msg,MsgName} ->
            FnName = gpb_lib:mk_fn(to_json_msg_, MsgName),
            ?expr('to_json_msg_...'('Value', 'TrUserData'),
                  [replace_term('to_json_msg_...', FnName),
                   replace_tree('Value', Var),
                   replace_tree('TrUserData', TrUserDataVar)]);
        {map,_KT,_VT} ->
            Var; % handled on a higher level
        {group,GName} ->
            FnName = gpb_lib:mk_fn(to_json_msg_, GName),
            ?expr('to_json_group_...'('Value', 'TrUserData'),
                  [replace_term('to_json_group_...', FnName),
                   replace_tree('Value', Var),
                   replace_tree('TrUserData', TrUserDataVar)])
    end.

%%% --- helpers ---

format_json_helpers(_Defs, #anres{map_types=MapTypes}=AnRes, Opts) ->
    HaveMapfields = sets:size(MapTypes) > 0,
    [case gpb_lib:json_object_format_by_opts(Opts) of
         eep18 ->
             format_eep18_object_helpers();
         {proplist} ->
             format_untagged_proplist_object_helpers();
         {Atom, proplist} ->
             format_tagged_proplist_object_helpers(Atom);
         map ->
             format_map_object_helpers(Opts)
     end,
     case gpb_lib:json_array_format_by_opts(Opts) of
         list ->
             format_plain_list_array_helpers();
         {Atom, list} ->
             format_tagged_list_array_helpers(Atom)
     end,
     [[case gpb_lib:get_records_or_maps_by_opts(Opts) of
           records ->
               format_mapfield_record_helpers();
           maps ->
               format_mapfield_map_helpers(Opts)
       end,
       format_mapfield_key_to_str_helpers()] || HaveMapfields],
     format_json_type_helpers(AnRes, Opts)].

%% -- object helpers --

format_eep18_object_helpers() ->
    ["%% eep18 object format helpers\n",
     "%% - proplist() % for non-empty objects\n"
     "%% - [{}]       % for empty objects\n"
     "%% For example jsx, eep18-conforming libs\n",
     gpb_lib:nowarn_unused_function(tj_new_object, 0),
     gpb_codegen:format_fn(
       tj_new_object,
       fun() -> [{}] end),
     gpb_lib:nowarn_unused_function(tj_add_field, 3),
     gpb_codegen:format_fn(
       tj_add_field,
       fun(FieldName, Value, [{}]) -> [{FieldName, Value}];
          (FieldName, Value, Object) -> [{FieldName, Value} | Object]
       end),
     gpb_lib:nowarn_unused_function(tj_finalize_obj, 1),
     gpb_codegen:format_fn(
       tj_finalize_obj,
       fun(Object) -> lists:reverse(Object) end)].

format_untagged_proplist_object_helpers() ->
    ["%% untagged proplist object format helpers\n",
     "%% - {proplist()}\n"
     "%% For example for jiffy\n",
     gpb_lib:nowarn_unused_function(tj_new_object, 0),
     gpb_codegen:format_fn(
       tj_new_object,
       fun() -> {[]} end),
     gpb_lib:nowarn_unused_function(tj_add_field, 3),
     gpb_codegen:format_fn(
       tj_add_field,
       fun(FieldName, Value, {Object}) ->
               {[{FieldName, Value} | Object]}
       end),
     gpb_lib:nowarn_unused_function(tj_finalize_obj, 1),
     gpb_codegen:format_fn(
       tj_finalize_obj,
       fun({Object}) -> {lists:reverse(Object)} end)].

format_tagged_proplist_object_helpers(Tag) ->
    ["%% tagged proplist object format helpers\n",
     "%% - {"++atom_to_list(Tag)++", proplist()}\n"
     "%% For example for mochjson2\n",
     gpb_lib:nowarn_unused_function(tj_new_object, 0),
     gpb_codegen:format_fn(
       tj_new_object,
       fun() -> {struct, []} end,
       [replace_term(struct, Tag)]),
     gpb_lib:nowarn_unused_function(tj_add_field, 3),
     gpb_codegen:format_fn(
       tj_add_field,
       fun(FieldName, Value, {struct, Object}) ->
               {struct, [{FieldName, Value} | Object]}
       end,
       [replace_term(struct, Tag)]),
     gpb_lib:nowarn_unused_function(tj_finalize_obj, 1),
     gpb_codegen:format_fn(
       tj_finalize_obj,
       fun({struct, Object}) -> {struct, lists:reverse(Object)} end,
       [replace_term(struct, Tag)])].

format_map_object_helpers(Opts) ->
    ["%% map object format helpers\n"
     "%% For example jsx, jiffy, others\n",
     gpb_lib:nowarn_unused_function(tj_new_object, 0),
     gpb_codegen:format_fn(
       tj_new_object,
       fun() -> '#{}' end,
       [replace_tree('#{}', gpb_lib:map_create([], Opts))]),
     gpb_lib:nowarn_unused_function(tj_add_field, 3),
     case gpb_lib:target_has_variable_key_map_update(Opts) of
         true ->
             {Object, FieldName, Value} =
                 {?expr(Object), ?expr(FieldName), ?expr(Value)},
             gpb_codegen:format_fn(
               tj_add_field,
               fun(FieldName, Value, Object) ->
                       'Object#{FieldName => Value}'
               end,
               [replace_tree(
                  'Object#{FieldName => Value}',
                  gpb_lib:map_set(Object, [{FieldName,Value}], []))]);
         false ->
             gpb_codegen:format_fn(
               tj_add_field,
               fun(FieldName, Value, Object) ->
                       maps:put(FieldName, Value, Object)
               end)
     end,
     gpb_lib:nowarn_unused_function(tj_finalize_obj, 1),
     gpb_codegen:format_fn(
       tj_finalize_obj,
       fun(Object) -> Object end)].

%% -- mapfield helpers, ie for map<_,_> --

format_mapfield_record_helpers() ->
    [gpb_lib:nowarn_unused_function(tj_mapfield_fold, 3),
     gpb_codegen:format_fn(
       tj_mapfield_fold,
       fun(TrElemF, ValueToJsonF, MapfieldElems) ->
               tj_finalize_obj(
                 lists:foldl(
                   fun(Elem, Obj) ->
                           {_, K, V} = TrElemF(Elem),
                           tj_add_field(tj_mapfield_key_to_str(K),
                                        ValueToJsonF(V),
                                        Obj)
                   end,
                   tj_new_object(),
                   MapfieldElems))
       end)].

format_mapfield_map_helpers(Opts) ->
    {K, V} = {?expr(K), ?expr(V)},
    [gpb_codegen:format_fn(
       tj_mapfield_fold,
       fun(TrElemF, ValueToJsonF, MapfieldElems) ->
               tj_finalize_obj(
                 lists:foldl(
                   fun(Elem, Obj) ->
                           '#{key := K, value := V}' = TrElemF(Elem),
                           tj_add_field(tj_mapfield_key_to_str(K),
                                        ValueToJsonF(V),
                                        Obj)
                   end,
                   tj_new_object(),
                   MapfieldElems))
       end,
       [replace_tree('#{key := K, value := V}',
                     gpb_lib:map_match([{key,K}, {value,V}], Opts))])].

format_mapfield_key_to_str_helpers() ->
    [gpb_lib:nowarn_unused_function(tj_mapfield_key_to_str, 1),
     gpb_codegen:format_fn(
       tj_mapfield_key_to_str,
       fun(N) when is_integer(N) -> tj_string(integer_to_list(N));
          (true) -> tj_string("true");
          (false) -> tj_string("false");
          (String) when is_list(String); is_binary(String) ->
               tj_string(String)
       end)].

%% -- array helpers --

format_plain_list_array_helpers() ->
    %% inline it?
    [gpb_lib:nowarn_unused_function(tj_array, 1),
     gpb_codegen:format_fn(tj_array,
                           fun(L) -> L end)].

format_tagged_list_array_helpers(Tag) ->
    %% inline it?
    [gpb_lib:nowarn_unused_function(tj_array, 1),
     gpb_codegen:format_fn(tj_array,
                           fun(L) -> {array, L} end,
                           [replace_term(array, Tag)])].

%% -- other helpers --

format_json_type_helpers(#anres{used_types=UsedTypes,
                                map_types=MapTypes}, Opts) ->
    HaveMapfields = sets:size(MapTypes) > 0,
    HaveInt64 = lists:any(fun(T) -> gpb_lib:smember(T, UsedTypes) end,
                          [sint64, int64, uint64, fixed64, sfixed64]),
    HaveEnum = lists:any(fun({enum,_}) -> true;
                            (_) -> false
                         end,
                         sets:to_list(UsedTypes)),
    NeedFloatType = lists:any(fun(T) -> gpb_lib:smember(T, UsedTypes) end,
                              [float, double]),
    %% map<_,_> keys are strings
    %% int64 types and enums also encode to strings
    NeedStringType = (gpb_lib:smember(string, UsedTypes)
                      orelse HaveMapfields
                      orelse HaveInt64
                      orelse HaveEnum),
    NeedBytesType = gpb_lib:smember(bytes, UsedTypes),

    [[gpb_codegen:format_fn(
        tj_float,
        %% Rely on the json libs to produce a good float
        %% (or should we produce a 15 digit %g as a string
        %% or by other means a roundtrip-able float-string?)
        fun(F) -> F
        end) || NeedFloatType],
     [case gpb_lib:json_string_format_by_opts(Opts) of
          binary ->
              [gpb_codegen:format_fn(
                 tj_string,
                 fun(Value) -> unicode:characters_to_binary(Value)
                 end)];
          list ->
              [gpb_codegen:format_fn(
                 tj_string,
                 fun(Value) -> unicode:characters_to_list(
                                 unicode:characters_to_binary(Value))
                 end)]
      end || NeedStringType],
     [gpb_codegen:format_fn(
        tj_bytes,
        fun(Value) -> base64:encode(iolist_to_binary(Value))
        end) || NeedBytesType]].

%% -- misc --

json_field_name(#?gpb_field{name=FName}=Field, Opts) ->
    JFName = case proplists:get_bool(json_preserve_proto_field_names, Opts) of
                 true  -> atom_to_list(FName);
                 false -> gpb_lib:get_field_json_name(Field)
             end,
    case gpb_lib:json_key_format_by_opts(Opts) of
        atom ->
            erl_syntax:atom(JFName);
        binary ->
            %% Want <<"fname">> and not <<102,110,97,109,101>>
            %% so make a text node
            erl_syntax:text(?ff("<<~p>>", [JFName]));
        string ->
            erl_syntax:string(JFName)
    end.
