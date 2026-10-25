package com.echo.hms;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;
import androidx.annotation.NonNull;

import com.huawei.hmf.tasks.OnFailureListener;
import com.huawei.hmf.tasks.OnSuccessListener;
import com.huawei.hmf.tasks.Task;
import com.huawei.hms.common.ApiException;
import com.huawei.hms.jos.AntiAddictionCallback;
import com.huawei.hms.jos.AppUpdateCallback;
import com.huawei.hms.jos.JosApps;
import com.huawei.hms.jos.JosAppsClient;
import com.huawei.hms.jos.games.Games;
import com.huawei.hms.jos.games.LeaderboardsClient;
import com.huawei.hms.jos.games.AchievementsClient;
import com.huawei.hms.jos.games.player.Player;
import com.huawei.hms.jos.games.player.PlayersClient;
import com.huawei.hms.support.account.AccountAuthManager;
import com.huawei.hms.support.account.request.AccountAuthParams;
import com.huawei.hms.support.account.request.AccountAuthParamsHelper;
import com.huawei.hms.support.account.result.AccountAuthResult;
import com.huawei.hms.support.account.result.AuthAccount;
import com.huawei.hms.support.account.service.AccountAuthService;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Native Godot 4.x Android Plugin bridging Huawei Mobile Services (HMS Core).
 * Provides Progressive On-Demand HUAWEI ID Authentication, Game Service Leaderboards,
 * and Achievements for ECHO.
 */
public class GodotHMS extends GodotPlugin {
    private static final String TAG = "GodotHMS";
    private static final int RC_SIGN_IN = 9001;

    private AccountAuthService mAuthService;
    private LeaderboardsClient mLeaderboardsClient;
    private AchievementsClient mAchievementsClient;
    private PlayersClient mPlayersClient;

    private boolean mIsSignedIn = false;
    private String mHuaweiId = "";
    private String mDisplayName = "Guest Explorer";

    public GodotHMS(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GodotHMS";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("on_sign_in_success", String.class, String.class)); // displayName, huaweiId
        signals.add(new SignalInfo("on_sign_in_failed", Integer.class, String.class));  // errorCode, errorMessage
        signals.add(new SignalInfo("on_sign_out_success"));
        signals.add(new SignalInfo("on_score_submitted", String.class, Long.class));    // leaderboardId, score
        signals.add(new SignalInfo("on_score_submit_failed", String.class, Integer.class));
        signals.add(new SignalInfo("on_achievement_unlocked", String.class));
        return signals;
    }

    /**
     * Initializes the Huawei Game Service SDK (called on game startup).
     */
    @UsedByGodot
    public void initGameService() {
        Activity activity = getActivity();
        if (activity == null) {
            Log.e(TAG, "Activity is null in initGameService");
            return;
        }

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    AccountAuthParams authParams = new AccountAuthParamsHelper(AccountAuthParams.DEFAULT_AUTH_REQUEST_PARAM_GAME)
                            .createParams();
                    mAuthService = AccountAuthManager.getService(getActivity(), authParams);

                    JosAppsClient appsClient = JosApps.getJosAppsClient(getActivity());
                    appsClient.init();
                    Log.i(TAG, "Huawei JosApps SDK initialized successfully.");
                } catch (Exception e) {
                    Log.e(TAG, "Failed to initialize Huawei JosApps SDK: " + e.getMessage());
                }
            }
        });
    }

    /**
     * Progressive On-Demand Sign In with HUAWEI ID.
     * Invoked only when user chooses to submit scores or view the global leaderboard.
     */
    @UsedByGodot
    public void signIn() {
        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (mAuthService == null) {
                    AccountAuthParams authParams = new AccountAuthParamsHelper(AccountAuthParams.DEFAULT_AUTH_REQUEST_PARAM_GAME)
                            .createParams();
                    mAuthService = AccountAuthManager.getService(getActivity(), authParams);
                }

                // First attempt silent sign-in
                Task<AuthAccount> silentTask = mAuthService.silentSignIn();
                silentTask.addOnSuccessListener(new OnSuccessListener<AuthAccount>() {
                    @Override
                    public void onSuccess(AuthAccount authAccount) {
                        handleAuthSuccess(authAccount);
                    }
                }).addOnFailureListener(new OnFailureListener() {
                    @Override
                    public void onFailure(Exception e) {
                        Log.i(TAG, "Silent sign-in failed, launching explicit HUAWEI ID intent.");
                        Intent signInIntent = mAuthService.getSignInIntent();
                        getActivity().startActivityForResult(signInIntent, RC_SIGN_IN);
                    }
                });
            }
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == RC_SIGN_IN) {
            Task<AuthAccount> authAccountTask = AccountAuthManager.parseAuthResultFromIntent(data);
            if (authAccountTask.isSuccessful()) {
                AuthAccount authAccount = authAccountTask.getResult();
                handleAuthSuccess(authAccount);
            } else {
                Exception e = authAccountTask.getException();
                int errCode = (e instanceof ApiException) ? ((ApiException) e).getStatusCode() : -1;
                String errMsg = (e != null) ? e.getMessage() : "Unknown authentication error";
                Log.e(TAG, "HUAWEI ID sign in failed: " + errCode + " - " + errMsg);
                emitSignal("on_sign_in_failed", errCode, errMsg);
            }
        }
    }

    private void handleAuthSuccess(AuthAccount authAccount) {
        mIsSignedIn = true;
        mHuaweiId = authAccount.getUnionId();
        mDisplayName = authAccount.getDisplayName();
        if (mDisplayName == null || mDisplayName.isEmpty()) {
            mDisplayName = "Huawei Explorer";
        }

        Activity activity = getActivity();
        mLeaderboardsClient = Games.getLeaderboardsClient(activity);
        mAchievementsClient = Games.getAchievementsClient(activity);
        mPlayersClient = Games.getPlayersClient(activity);

        Log.i(TAG, "HUAWEI ID Sign in success: " + mDisplayName + " (" + mHuaweiId + ")");
        emitSignal("on_sign_in_success", mDisplayName, mHuaweiId);
    }

    /**
     * Sign out from HUAWEI ID.
     */
    @UsedByGodot
    public void signOut() {
        if (mAuthService != null) {
            mAuthService.signOut().addOnSuccessListener(new OnSuccessListener<Void>() {
                @Override
                public void onSuccess(Void aVoid) {
                    mIsSignedIn = false;
                    mHuaweiId = "";
                    mDisplayName = "Guest Explorer";
                    Log.i(TAG, "Signed out from HUAWEI ID.");
                    emitSignal("on_sign_out_success");
                }
            });
        }
    }

    /**
     * Submit level escape time to Huawei Game Service Leaderboard.
     * @param leaderboardId Leaderboard ID configured in AppGallery Connect
     * @param scoreMillis Escape time in milliseconds (lower is better)
     */
    @UsedByGodot
    public void submitScore(final String leaderboardId, final long scoreMillis) {
        if (!mIsSignedIn || mLeaderboardsClient == null) {
            Log.w(TAG, "Cannot submit score: Player is not signed into HUAWEI ID.");
            return;
        }

        Task<ScoreSubmissionResult> task = mLeaderboardsClient.submitScoreWithResult(leaderboardId, scoreMillis);
        task.addOnSuccessListener(new OnSuccessListener<ScoreSubmissionResult>() {
            @Override
            public void onSuccess(ScoreSubmissionResult result) {
                Log.i(TAG, "Score submitted to Huawei Leaderboard: " + leaderboardId + " -> " + scoreMillis + "ms");
                emitSignal("on_score_submitted", leaderboardId, scoreMillis);
            }
        }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(Exception e) {
                int errCode = (e instanceof ApiException) ? ((ApiException) e).getStatusCode() : -1;
                Log.e(TAG, "Failed to submit score to Huawei Leaderboard: " + errCode);
                emitSignal("on_score_submit_failed", leaderboardId, errCode);
            }
        });
    }

    /**
     * Unlock an achievement in Huawei Game Service.
     */
    @UsedByGodot
    public void unlockAchievement(final String achievementId) {
        if (!mIsSignedIn || mAchievementsClient == null) {
            return;
        }

        mAchievementsClient.reachWithResult(achievementId).addOnSuccessListener(new OnSuccessListener<Void>() {
            @Override
            public void onSuccess(Void aVoid) {
                Log.i(TAG, "Achievement unlocked on Huawei Game Service: " + achievementId);
                emitSignal("on_achievement_unlocked", achievementId);
            }
        });
    }

    @UsedByGodot
    public boolean isSignedIn() {
        return mIsSignedIn;
    }

    @UsedByGodot
    public String getDisplayName() {
        return mDisplayName;
    }

    @UsedByGodot
    public String getHuaweiId() {
        return mHuaweiId;
    }
}
