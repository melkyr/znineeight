# mi_matrix corpus — expected-fail manifest (v3 Task 5)
# Baseline 8534627b: 55 OK / 54 gccfail / 1 catchfail / 22 crash
# After v3 delegation+joins (adcb77ce): 72 OK / 37 gccfail / 1 catchfail / 22 crash (zero regression, +17 OK)
# All entries below are PRE-EXISTING upstream failures OUTSIDE 'wrap kinds only' scope.

## CRASH (pre-existing compiler crash — if_expr / opteu shapes):
eu_err_if_expr
eu_val_if_expr
eunum_err_if_expr
eunum_val_if_expr
euopt_err_if_expr
euopt_val_if_expr
euoptptr_err_if_expr
euoptptr_val_if_expr
euvoid_val_catch
opteu_err_if_expr
opteu_err_switch
opteu_null_assign
opteu_null_if_expr
opteu_null_orelse
opteu_null_switch
opteu_val_assign
opteu_val_call_arg
opteu_val_catch
opteu_val_orelse
opteu_val_return
opteu_val_switch
opteu_val_var_decl

## CATCHFAIL (deferred catch-merge bug lower.zig:2268):
euoptptr_err_catch

## GCCFAIL non-catch (nested-opt flattening / decl_local / type-name emission — pre-existing):
eu_err_assign
eu_err_var_decl
eu_val_assign
eu_val_switch
eu_val_var_decl
eunum_err_assign
eunum_err_var_decl
eunum_val_assign
eunum_val_switch
eunum_val_var_decl
euopt_err_assign
euopt_err_var_decl
euopt_val_assign
euopt_val_switch
euopt_val_var_decl
euoptptr_err_assign
euoptptr_err_call_arg
euoptptr_err_var_decl
euoptptr_val_assign
euoptptr_val_orelse
euoptptr_val_switch
euoptptr_val_var_decl
opt_null_if_expr
opt_val_if_expr
opteu_null_var_decl
optnum_null_if_expr
optnum_val_if_expr
optopt_null_assign
optopt_null_if_expr
optopt_val_assign
optopt_val_call_arg
optopt_val_if_expr
optopt_val_var_decl
optptr_null_if_expr
optptr_null_orelse
optptr_val_if_expr
optptr_val_orelse
