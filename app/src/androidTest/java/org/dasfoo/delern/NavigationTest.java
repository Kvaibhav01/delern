/*
 * Copyright (C) 2017 Katarina Sheremet
 * This file is part of Delern.
 *
 * Delern is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * Delern is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with  Delern.  If not, see <http://www.gnu.org/licenses/>.
 */

package org.dasfoo.delern;


import android.app.Activity;
import android.app.Instrumentation;
import android.support.test.espresso.contrib.DrawerActions;
import android.support.test.espresso.contrib.NavigationViewActions;
import android.support.test.espresso.intent.rule.IntentsTestRule;

import org.dasfoo.delern.listdecks.DelernMainActivity;
import org.dasfoo.delern.test.FirebaseOperationInProgressRule;
import org.junit.Rule;
import org.junit.Test;

import static android.support.test.espresso.Espresso.onView;
import static android.support.test.espresso.action.ViewActions.click;
import static android.support.test.espresso.assertion.ViewAssertions.matches;
import static android.support.test.espresso.intent.Intents.intended;
import static android.support.test.espresso.intent.Intents.intending;
import static android.support.test.espresso.intent.matcher.IntentMatchers.hasAction;
import static android.support.test.espresso.intent.matcher.IntentMatchers.toPackage;
import static android.support.test.espresso.matcher.RootMatchers.withDecorView;
import static android.support.test.espresso.matcher.ViewMatchers.isDisplayed;
import static android.support.test.espresso.matcher.ViewMatchers.withId;
import static android.support.test.espresso.matcher.ViewMatchers.withText;
import static org.dasfoo.delern.test.WaitView.waitView;
import static org.hamcrest.CoreMatchers.allOf;
import static org.hamcrest.CoreMatchers.not;


/**
 * Test Navigation Drawer
 */
public class NavigationTest {

    @Rule
    public IntentsTestRule<DelernMainActivity> mActivityRule = new IntentsTestRule<>(
            DelernMainActivity.class);

    @Rule
    public FirebaseOperationInProgressRule mFirebaseRule = new FirebaseOperationInProgressRule();

    @Test
    public void openNavigationDrawer() {
        waitView(withId(R.id.fab)).check(matches(isDisplayed()));
        onView(withId(R.id.drawer_layout)).perform(DrawerActions.open());
        waitView(withId(R.id.nav_view)).check(matches(isDisplayed()));
        onView(withId(R.id.drawer_layout)).perform(DrawerActions.close());
    }

    @Test
    public void signOut() {
        waitView(withId(R.id.fab)).check(matches(isDisplayed()));
        onView(withId(R.id.drawer_layout)).perform(DrawerActions.open());
        waitView(withId(R.id.nav_view)).check(matches(isDisplayed()));
        waitView(withId(R.id.nav_view))
                .perform(NavigationViewActions.navigateTo(R.id.nav_sign_out));
        onView(withText(R.string.sign_out)).check(matches(isDisplayed()));
        onView(withText(R.string.sign_out)).perform(click());
    }

    @Test
    public void inviteWasNotSent() {
        Instrumentation.ActivityResult result = new Instrumentation
                .ActivityResult(Activity.RESULT_CANCELED, null);
        intending(toPackage("com.google.android.gms")).respondWith(result);
        waitView(withId(R.id.fab)).check(matches(isDisplayed()));
        onView(withId(R.id.drawer_layout)).perform(DrawerActions.open());
        waitView(withId(R.id.nav_view)).check(matches(isDisplayed()));
        onView(withId(R.id.nav_view))
                .perform(NavigationViewActions.navigateTo(R.id.nav_invite));
        intended(allOf(hasAction("com.google.android.gms.appinvite.ACTION_APP_INVITE"),
                toPackage("com.google.android.gms")));
        onView(withText(R.string.invitation_failed_message))
                .inRoot(withDecorView(not(mActivityRule.getActivity().getWindow().getDecorView())))
                .check(matches(isDisplayed()));
    }

    @Test
    public void inviteSent() {
        Instrumentation.ActivityResult result = new Instrumentation
                .ActivityResult(Activity.RESULT_OK, null);
        intending(toPackage("com.google.android.gms")).respondWith(result);
        waitView(withId(R.id.fab)).check(matches(isDisplayed()));
        onView(withId(R.id.drawer_layout)).perform(DrawerActions.open());
        waitView(withId(R.id.nav_view)).check(matches(isDisplayed()));
        onView(withId(R.id.nav_view))
                .perform(NavigationViewActions.navigateTo(R.id.nav_invite));
        intended(allOf(hasAction("com.google.android.gms.appinvite.ACTION_APP_INVITE"),
                toPackage("com.google.android.gms")));
        onView(withText(R.string.invitation_sent_message))
                .inRoot(withDecorView(not(mActivityRule.getActivity().getWindow().getDecorView())))
                .check(matches(isDisplayed()));
    }
}