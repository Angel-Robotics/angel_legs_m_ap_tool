package com.angelrobotics.flutter.angel.legs.m.ap.flutter_angel_legs_m_ap_tool

import android.os.Bundle
import com.polidea.rxandroidble2.exceptions.BleException
import io.flutter.embedding.android.FlutterActivity
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        RxJavaPlugins.setErrorHandler { throwable ->
            if (throwable is UndeliverableException && throwable.cause is BleException) {
                return@setErrorHandler // ignore BleExceptions since we do not have subscriber
            } else {
                throw throwable
            }
        }
    }
}
