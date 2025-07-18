package com.example.fieldframe;

import android.content.Intent;
import android.os.Bundle;
import androidx.annotation.Nullable;
import io.flutter.embedding.android.FlutterActivity;

public class DeepLinkActivity extends FlutterActivity {
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Forward the intent to MainActivity
        Intent intent = new Intent(this, MainActivity.class);
        intent.setData(getIntent().getData());
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
        finish();
    }
}