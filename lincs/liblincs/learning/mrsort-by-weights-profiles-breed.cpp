// Copyright 2023-2024 Vincent Jacques

#include "mrsort-by-weights-profiles-breed.hpp"

#ifndef NDEBUG
#include <iostream>
#endif
#include <map>
#include <numeric>

#include "../chrones.hpp"
#include "../unreachable.hpp"
#include "exception.hpp"


namespace lincs {

LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::ModelsBeingLearned(
    const PreprocessedLearningSet& preprocessed_learning_set_,
    const unsigned models_count_,
    const unsigned random_seed
) :
  preprocessed_learning_set(preprocessed_learning_set_),
  models_count(models_count_),
  random_generators(models_count),
  iteration_index(0),
  model_indexes(models_count),
  accuracies(models_count, zeroed),
  low_profile_ranks(models_count, preprocessed_learning_set.boundaries_count, preprocessed_learning_set.criteria_count, uninitialized),
  single_peaked_criteria_count(count_single_peaked_criteria()),
  high_profile_rank_indexes(preprocessed_learning_set.criteria_count, uninitialized),
  high_profile_ranks(models_count, preprocessed_learning_set.boundaries_count, single_peaked_criteria_count, uninitialized),
  weights(models_count, preprocessed_learning_set.criteria_count, uninitialized),
  best_model_accuracy(0),
  best_model_low_profile_ranks(preprocessed_learning_set.boundaries_count, preprocessed_learning_set.criteria_count, uninitialized),
  best_model_high_profile_ranks(preprocessed_learning_set.boundaries_count, single_peaked_criteria_count, uninitialized),
  best_model_weights(preprocessed_learning_set.criteria_count, uninitialized)
{
  CHRONE();

  std::iota(model_indexes.begin(), model_indexes.end(), 0);

  for (unsigned model_index = 0; model_index != models_count; ++model_index) {
    random_generators[model_index].seed(random_seed * (model_index + 1));
  }

  unsigned count = 0;
  for (unsigned criterion_index = 0; criterion_index != preprocessed_learning_set.criteria_count; ++criterion_index) {
    if (preprocessed_learning_set.single_peaked[criterion_index]) {
      high_profile_rank_indexes[criterion_index] = count;
      ++count;
    }
  }
  assert(high_profile_ranks.s0() == count);
}

unsigned LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::count_single_peaked_criteria() const {
  unsigned count = 0;
  for (unsigned criterion_index = 0; criterion_index != preprocessed_learning_set.criteria_count; ++criterion_index) {
    if (preprocessed_learning_set.single_peaked[criterion_index]) {
      ++count;
    }
  }
  return count;
}

Model LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::make_model(
  ArrayView2D<Host, const unsigned> low_profile_ranks,
  ArrayView2D<Host, const unsigned> high_profile_ranks,
  ArrayView1D<Host, const float> weights
) const {
  CHRONE();

  std::vector<float> model_weights;
  model_weights.reserve(preprocessed_learning_set.criteria_count);
  for (unsigned criterion_index = 0; criterion_index != preprocessed_learning_set.criteria_count; ++criterion_index) {
    model_weights.push_back(weights[criterion_index]);
  }
  SufficientCoalitions coalitions = SufficientCoalitions(SufficientCoalitions::Weights(model_weights));

  std::vector<PreprocessedBoundary> boundaries;
  boundaries.reserve(preprocessed_learning_set.boundaries_count);
  for (unsigned boundary_index = 0; boundary_index != preprocessed_learning_set.boundaries_count; ++boundary_index) {
    std::vector<std::variant<unsigned, std::pair<unsigned, unsigned>>> boundary_profile;
    boundary_profile.reserve(preprocessed_learning_set.criteria_count);
    for (unsigned criterion_index = 0; criterion_index != preprocessed_learning_set.criteria_count; ++criterion_index) {
      const unsigned low_profile_rank = low_profile_ranks[boundary_index][criterion_index];
      if (preprocessed_learning_set.single_peaked[criterion_index]) {
        const unsigned high_profile_rank = high_profile_ranks[boundary_index][high_profile_rank_indexes[criterion_index]];
        boundary_profile.push_back(std::make_pair(low_profile_rank, high_profile_rank));
      } else {
        boundary_profile.push_back(low_profile_rank);
      }
    }
    boundaries.emplace_back(boundary_profile, coalitions);
  }

  return preprocessed_learning_set.post_process(boundaries);
}

#ifndef NDEBUG
bool LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::model_is_correct(const unsigned model_index) const {
  try {
    make_model(low_profile_ranks[model_index], high_profile_ranks[model_index], weights[model_index]);
  } catch (const DataValidationException& e) {
    std::cerr << "Model " << model_index << " is incorrect: " << e.what() << std::endl;
    return false;
  }
  return true;
}

bool LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::models_are_correct() const {
  for (unsigned model_index = 0; model_index != models_count; ++model_index) {
    if (!model_is_correct(model_index)) {
      return false;
    }
  }
  return true;
}
#endif


Model LearnMrsortByWeightsProfilesBreed::perform() {
  CHRONE();

  if (models_being_learned.single_peaked_criteria_count != 0) {
    if (!profiles_initialization_strategy.supports_single_peaked_criteria) {
      throw LearningFailureException("This profiles initialization strategy doesn't support single-peaked criteria.");
    }
    if (!weights_optimization_strategy.supports_single_peaked_criteria) {
      throw LearningFailureException("This weights optimization strategy doesn't support single-peaked criteria.");
    }
    if (!profiles_improvement_strategy.supports_single_peaked_criteria) {
      throw LearningFailureException("This profiles improvement strategy doesn't support single-peaked criteria.");
    }
    if (!breeding_strategy.supports_single_peaked_criteria) {
      throw LearningFailureException("This breeding strategy doesn't support single-peaked criteria.");
    }
  }

  profiles_initialization_strategy.initialize_profiles(0, models_being_learned.models_count);
  weights_optimization_strategy.optimize_weights(0, models_being_learned.models_count);

  assert(models_being_learned.models_are_correct());

  while (true) {
    // @todo(Performance, later) Consider keeping the common part of all LPs in memory, and use it as a base for the LPs.
    // (The part that comes from the structure of the problem, and the part that comes from the learing set: they are always the same.)

    // @todo(Performance, later) Consider modifying the linear programs instead of regenerating them.
    // We know what profiles have changed since the last iteration, so maybe we could just update the constraints.

    // @todo(Performance, later) Consider stopping the LP optimization after the first phase,
    // i.e. when we have the first feasible solution. Maybe we don't need the optimal solution?

    profiles_improvement_strategy.improve_profiles(0, models_being_learned.models_count);
    weights_optimization_strategy.optimize_weights(0, models_being_learned.models_count);

    assert(models_being_learned.models_are_correct());

    // Sort model_indexes by increasing model accuracy
    for (unsigned model_index = 0; model_index != models_being_learned.models_count; ++model_index) {
      models_being_learned.recompute_accuracy(model_index);
    }
    std::sort(
      models_being_learned.model_indexes.begin(), models_being_learned.model_indexes.end(),
      [this](unsigned left_model_index, unsigned right_model_index) {
        return models_being_learned.accuracies[left_model_index] < models_being_learned.accuracies[right_model_index];
      }
    );

    // Keep the best model
    const unsigned best_model_index = models_being_learned.model_indexes.back();
    const unsigned current_best_accuracy = models_being_learned.accuracies[best_model_index];
    if (current_best_accuracy > models_being_learned.best_model_accuracy) {
      models_being_learned.best_model_accuracy = models_being_learned.accuracies[best_model_index];
      copy(models_being_learned.low_profile_ranks[best_model_index], ref(models_being_learned.best_model_low_profile_ranks));
      copy(models_being_learned.high_profile_ranks[best_model_index], ref(models_being_learned.best_model_high_profile_ranks));
      copy(models_being_learned.weights[best_model_index], ref(models_being_learned.best_model_weights));
    }

    // Succeed?
    if (models_being_learned.get_best_accuracy() == preprocessed_learning_set.alternatives_count || termination_strategy.terminate()) {
      for (auto observer : observers) {
        observer->before_return();
      }
      return models_being_learned.get_best_model();
    }

    // Breed
    // @todo(Feature, later) Keep the best model and reinit half of the others
    breeding_strategy.breed();

    // Observe
    for (auto observer : observers) {
      observer->after_iteration();
    }

    ++models_being_learned.iteration_index;
  }

  unreachable();
}

unsigned LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::compute_accuracy(const unsigned model_index) const {
  unsigned accuracy = 0;

  for (unsigned alternative_index = 0; alternative_index != preprocessed_learning_set.alternatives_count; ++alternative_index) {
    if (is_correctly_assigned(model_index, alternative_index)) {
      ++accuracy;
    }
  }

  return accuracy;
}

bool LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::is_correctly_assigned(
  const unsigned model_index,
  const unsigned alternative_index
) const {
  const unsigned expected_assignment = preprocessed_learning_set.assignments[alternative_index];
  const unsigned actual_assignment = get_assignment(model_index, alternative_index);

  return actual_assignment == expected_assignment;
}

bool LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::is_accepted(
  const unsigned model_index,
  const unsigned boundary_index,
  const unsigned criterion_index,
  const unsigned alternative_index
) const {
  const unsigned alternative_rank = preprocessed_learning_set.performance_ranks[criterion_index][alternative_index];
  const unsigned low_profile_rank = low_profile_ranks[model_index][boundary_index][criterion_index];
  if (preprocessed_learning_set.single_peaked[criterion_index]) {
    const unsigned high_profile_rank = high_profile_ranks[model_index][boundary_index][high_profile_rank_indexes[criterion_index]];
    return low_profile_rank <= alternative_rank && alternative_rank <= high_profile_rank;
  } else {
    return low_profile_rank <= alternative_rank;
  }
}

unsigned LearnMrsortByWeightsProfilesBreed::ModelsBeingLearned::get_assignment(const unsigned model_index, const unsigned alternative_index) const {
  // @todo(Performance, later) Evaluate if it's worth storing and updating the models' assignments
  // (instead of recomputing them here)
  // Same question in accuracy-heuristic-on-gpu.cu
  assert(model_index < models_count);
  assert(alternative_index < preprocessed_learning_set.alternatives_count);

  // Not parallelizable in this form because the loop gets interrupted by a return. But we could rewrite it
  // to always perform all its iterations, and then it would be yet another map-reduce, with the reduce
  // phase keeping the maximum 'category_index' that passes the weight threshold.
  for (unsigned category_index = preprocessed_learning_set.categories_count - 1; category_index != 0; --category_index) {
    const unsigned boundary_index = category_index - 1;
    float accepted_weight = 0;
    for (unsigned criterion_index = 0; criterion_index != preprocessed_learning_set.criteria_count; ++criterion_index) {
      if (is_accepted(model_index, boundary_index, criterion_index, alternative_index)) {
        accepted_weight += weights[model_index][criterion_index];
      }
    }
    if (accepted_weight >= 1) {
      return category_index;
    }
  }
  return 0;
}

}  // namespace lincs
