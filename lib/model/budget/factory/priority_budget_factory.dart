import 'package:budgetflow/model/budget/budget.dart';
import 'package:budgetflow/model/budget/budget_map.dart';
import 'package:budgetflow/model/budget/budget_type.dart';
import 'package:budgetflow/model/budget/category/category.dart';
import 'package:budgetflow/model/budget/factory/budget_factory.dart';

class _NSW {
  double needs, savings, wants;

  _NSW(double needs, savings, wants) {
    this.needs = needs;
    this.savings = savings;
    this.wants = wants;
  }

  void multiply(double n) {
    needs *= n;
    savings *= n;
    wants *= n;
  }

  void divide(double n) {
    if (n == 0) return;
    needs /= n;
    savings /= n;
    wants /= n;
  }
}

class PriorityBudgetFactory implements BudgetFactory {
  static _NSW _stage1Depletion = new _NSW(.6, .0, .4);
  static _NSW _stage2Depletion = new _NSW(.75, .0, .25);
  static _NSW _stage3Depletion = new _NSW(.9, .0, .1);
  static _NSW _stage4Depletion = new _NSW(.95, .0, .05);
  static _NSW _stage1Growth = new _NSW(.5, .2, .3);
  static _NSW _stage2Growth = new _NSW(.65, .2, .15);
  static _NSW _stage3Growth = new _NSW(.85, .05, .1);
  static _NSW _stage4Growth = new _NSW(.94, .01, .05);
  static const _stage1Bound = .3;
  static const _stage2Bound = .5;
  static const _stage3Bound = .8;
  static const _stage4Bound = 1.0;

  double _housingRatio = 0.0,
      _income = 0.0,
      _underspending = 0.0,
      _overspending = 0.0;
  _NSW _currentDistribution, _targetDistribution;
  double _wantsRatio, _needsRatio, _savingsRatio;
  Budget _oldBudget;
  BudgetMap _oldAllotmentRatios = new BudgetMap(),
      _oldActualRatios = new BudgetMap(),
      _spendingDiffs = new BudgetMap(),
      _newAllotmentRatios = new BudgetMap(),
      _allottedSpending = new BudgetMap(),
      _targetSpending = new BudgetMap();

  PriorityBudgetFactory();

  @override
  Budget newFromInfo(double income, double housing, bool depletion,
      double savingsPull, bool kids, bool pets) {
    var type;
    if (depletion)
      type = BudgetType.depletion;
    else
      type = BudgetType.growth;
    _currentDistribution = new _NSW(0.0, 0.0, 0.0);
    _targetDistribution = new _NSW(0.0, 0.0, 0.0);
    _housingRatio = housing / income;
    _income = income;
    _decidePlan(type);
    _setAllotments(housing);
  }

  void _decidePlan(BudgetType type) {
    switch (type) {
      case BudgetType.depletion:
        _setBudgetDepletionRatios();
        break;
      case BudgetType.growth:
        _setBudgetGrowthRatios();
        break;
    }
  }

  void _setBudgetDepletionRatios() {
    if (_housingRatio <= _stage1Bound) {
      _currentDistribution = _stage1Depletion;
      _targetDistribution = _stage1Depletion;
    } else if (_housingRatio <= _stage2Bound) {
      _currentDistribution = _stage2Depletion;
      _targetDistribution = _stage1Depletion;
    } else if (_housingRatio <= _stage3Bound) {
      _currentDistribution = _stage3Depletion;
      _targetDistribution = _stage2Depletion;
    } else if (_housingRatio <= _stage4Bound) {
      _currentDistribution = _stage4Depletion;
      _targetDistribution = _stage3Depletion;
    }
  }

  void _setBudgetGrowthRatios() {
    if (_housingRatio <= _stage1Bound) {
      _currentDistribution = _stage1Growth;
      _targetDistribution = _stage1Growth;
    } else if (_housingRatio <= _stage2Bound) {
      _currentDistribution = _stage2Growth;
      _targetDistribution = _stage1Growth;
    } else if (_housingRatio <= _stage3Bound) {
      _currentDistribution = _stage3Growth;
      _targetDistribution = _stage2Growth;
    } else if (_housingRatio <= _stage4Bound) {
      _currentDistribution = _stage4Growth;
      _targetDistribution = _stage3Growth;
    }
  }

  void _setAllotments(double housing) {
    // Allocate housing before anything else
    _allottedSpending[Category.housing] = housing;
    // Get number of categories in needs and wants
    // TODO finish
    _needsRatio = _currentDistribution.needs - _housingRatio;
    _wantsRatio = _currentDistribution.wants;
    _savingsRatio = _currentDistribution.savings;
    double dNeedsRatio = _income * _needsRatio / 4.0;
    double dWantsRatio = _income * _wantsRatio / 5.0;
    _allottedSpending[Category.utilities] = dNeedsRatio;
    _allottedSpending[Category.groceries] = dNeedsRatio;
    _allottedSpending[Category.health] = dNeedsRatio;
    _allottedSpending[Category.transportation] = dNeedsRatio;
    _allottedSpending[Category.education] = dWantsRatio;
    _allottedSpending[Category.entertainment] = dWantsRatio;
    _allottedSpending[Category.kids] = dWantsRatio;
    _allottedSpending[Category.pets] = dWantsRatio;
    _allottedSpending[Category.miscellaneous] = dWantsRatio;
    _allottedSpending[Category.savings] = _savingsRatio * _income;
  }

  @override
  Budget newFromBudget(Budget old) {
    _oldBudget = old;
    _income = old.expectedIncome;
    _oldAllotmentRatios = old.allotted.divide(_income);
    _oldActualRatios = old.actual.divide(_income);
    if (_userExceededBudget()) {
      // Return the same budget as last month
      return Budget.from(old);
    }
    // Look at spending, see what fields were over and what were under
    _findSpendingDiffs();
    // Reorganize funds between over and under fields, put the rest into savings
    _reallocate();
    _setAllotmentsForNextMonth();
    return Budget(
      expectedIncome: old.expectedIncome,
      type: old.type,
      // TODO update target based on old budget
      target: old.target,
      allotted: _allottedSpending,
    );
  }

  bool _userExceededBudget() {
    double total = 0.0;
    _oldActualRatios.forEach((Category c, double d) {
      total += d;
    });
    return total > _income;
  }

  void _findSpendingDiffs() {
    _spendingDiffs = new BudgetMap();
    _oldAllotmentRatios.forEach((Category c, double d) {
      double allotted = d;
      double spent = _oldActualRatios[c];
      if (_oldActualRatios[c] != d) {
        _spendingDiffs[c] = spent - allotted;
      }
    });
  }

  void _reallocate() {
    _newAllotmentRatios = new BudgetMap();
    _spendingDiffs.forEach((Category c, double d) {
      if (c != Category.savings) {
        if (d < 0.0) _underspending += d;
        if (d > 0.0) _overspending += d;
      }
    });
    _spendingDiffs.forEach((Category c, double d) {
      if (c != Category.savings) {
        _reallocateCategory(c, d);
      }
    });
    double leftover = -_underspending;
    _newAllotmentRatios[Category.savings] =
        _oldAllotmentRatios[Category.savings] + leftover;
  }

  void _reallocateCategory(Category c, double d) {
    if (d < 0.0) {
      _newAllotmentRatios[c] = _oldAllotmentRatios[c] + d / _overspending;
      _underspending -= d / _overspending;
    }
    if (d >= 0.0) {
      _newAllotmentRatios[c] = _oldActualRatios[c];
    }
  }

  void _setAllotmentsForNextMonth() {
    _oldBudget.allotted.keys.forEach((Category c) {
      _allottedSpending[c] = _newAllotmentRatios[c] * _income;
    });
  }
}
