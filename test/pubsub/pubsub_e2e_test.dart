// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:gcloud/pubsub.dart';
import 'package:googleapis/common/common.dart' as common;
import 'package:unittest/unittest.dart';

import '../common_e2e.dart';

runTests(PubSub pubsub, String project, String prefix) {
  String generateTopicName() {
    var id = new DateTime.now().millisecondsSinceEpoch;
    return '$prefix-topic-$id';
  }

  String generateSubscriptionName() {
    var id = new DateTime.now().millisecondsSinceEpoch;
    return '$prefix-subscription-$id';
  }

  group('topic', () {
    test('create-lookup-delete', () async {
      var topicName = generateTopicName();
      var topic = await pubsub.createTopic(topicName);
      expect(topic.name, topicName);
      topic = await pubsub.lookupTopic(topicName);
      expect(topic.name, topicName);
      expect(topic.project, project);
      expect(topic.absoluteName, 'projects/$project/topics/$topicName');
      expect(await pubsub.deleteTopic(topicName), isNull);
    });

    solo_test('create-list-delete', () async {
      const int count = 5;

      var topicPrefix = generateTopicName();

      name(i) => '$topicPrefix-$i';

      for (var i = 0; i < count; i++) {
        await pubsub.createTopic(name(i));
      }
      var topics = await pubsub.listTopics().map((t) => t.name).toList();
      for (var i = 0; i < count; i++) {
        expect(topics.contains(name(i)), isTrue);
        await pubsub.deleteTopic(name(i));
      }
    });
  });

  group('subscription', () {
    test('create-lookup-delete', () async {
      var topicName = generateTopicName();
      var subscriptionName = generateSubscriptionName();
      var topic = await pubsub.createTopic(topicName);
      var subscription =
          await pubsub.createSubscription(subscriptionName, topicName);
      expect(subscription.name, subscriptionName);
      subscription = await pubsub.lookupSubscription(subscriptionName);
      expect(subscription.name, subscriptionName);
      expect(subscription.project, project);
      expect(subscription.absoluteName,
             'projects/$project/subscriptions/$subscriptionName');
      expect(subscription.isPull, isTrue);
      expect(subscription.isPush, isFalse);
      expect(await pubsub.deleteSubscription(subscriptionName), isNull);
      expect(await pubsub.deleteTopic(topicName), isNull);
    });

    test('create-list-delete', () async {
      const int count = 5;
      var topicName = generateTopicName();
      var topic = await pubsub.createTopic(topicName);

      var subscriptionPrefix = generateSubscriptionName();

      name(i) => '$subscriptionPrefix-$i';

      for (var i = 0; i < count; i++) {
        await pubsub.createSubscription(name(i), topicName);
      }
      var subscriptions =
          await pubsub.listSubscriptions().map((t) => t.name).toList();
      for (var i = 0; i < count; i++) {
        expect(subscriptions.contains(name(i)), isTrue);
        await pubsub.deleteSubscription(name(i));
      }
      await pubsub.deleteTopic(topicName);
    });

    test('push-pull', () async {
      var topicName = generateTopicName();
      var subscriptionName = generateSubscriptionName();
      var topic = await pubsub.createTopic(topicName);
      var subscription =
          await pubsub.createSubscription(subscriptionName, topicName);
      expect(await subscription.pull(), isNull);

      expect(await topic.publishString('Hello, world!'), isNull);
      var pullEvent = await subscription.pull();
      expect(pullEvent, isNotNull);
      expect(pullEvent.message.asString, 'Hello, world!');
      expect(await pullEvent.acknowledge(), isNull);

      await pubsub.deleteSubscription(subscriptionName);
      await pubsub.deleteTopic(topicName);
    });
  });
}

main() {
  // Generate a unique prefix for all names generated by the tests.
  var id = new DateTime.now().millisecondsSinceEpoch;
  var prefix = 'dart-e2e-test-$id';

  withAuthClient(PubSub.SCOPES, (String project, httpClient) async {
    // Share the same pubsub connection for all tests.
    bool leftovers = false;
    var pubsub = new PubSub(httpClient, project);
    try {
      await runE2EUnittest(() {
        runTests(pubsub, project, prefix);
      });
    } finally {
      // Try to delete any leftover subscriptions from the tests.
      var subscriptions = await pubsub.listSubscriptions().toList();
      for (var subscription in subscriptions) {
        if (subscription.name.startsWith(prefix)) {
          try {
            print('WARNING: Removing leftover subscription '
                  '${subscription.name}');
            leftovers = true;
            await pubsub.deleteSubscription(subscription.name);
          } catch (e) {
            print('Error during test cleanup of subscription '
                  '${subscription.name} ($e)');
          }
        }
      }
      // Try to delete any leftover topics from the tests.
      var topics = await pubsub.listTopics().toList();
      for (var topic in topics) {
        if (topic.name.startsWith(prefix)) {
          try {
            print('WARNING: Removing leftover topic ${topic.name}');
            leftovers = true;
            await pubsub.deleteTopic(topic.name);
          } catch (e) {
            print('Error during test cleanup of topic ${topic.name} ($e)');
          }
        }
      }
    }

    if (leftovers) {
      throw 'Test terminated with leftover topics and/or subscriptions';
    }
  });
}
